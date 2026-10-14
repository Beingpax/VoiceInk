using System.Buffers.Binary;

namespace VoiceInk.Core.Audio;

public enum SampleFormat { F32, I16, I24, I32 }

public sealed record DecodedWav(int SampleRate, float[] Samples);

public static class AudioConvert
{
    public const int TargetSampleRate = 16_000;

    public static int BytesPerSample(this SampleFormat f) => f switch
    {
        SampleFormat.I16 => 2,
        SampleFormat.I24 => 3,
        _ => 4,
    };

    /// <summary>Converts interleaved little-endian PCM/float frames to mono floats in -1..1.</summary>
    public static float[] DownmixToMono(ReadOnlySpan<byte> bytes, SampleFormat format, int channels)
    {
        channels = Math.Max(1, channels);
        var sample = format.BytesPerSample();
        var frame = sample * channels;
        var frames = bytes.Length / frame;
        var output = new float[frames];
        for (var i = 0; i < frames; i++)
        {
            var sum = 0f;
            for (var c = 0; c < channels; c++)
            {
                var ch = bytes.Slice((i * frame) + (c * sample), sample);
                sum += format switch
                {
                    SampleFormat.F32 => BinaryPrimitives.ReadSingleLittleEndian(ch),
                    SampleFormat.I16 => BinaryPrimitives.ReadInt16LittleEndian(ch) / 32768f,
                    SampleFormat.I24 => (((ch[0] << 8) | (ch[1] << 16) | (ch[2] << 24)) >> 8) / 8_388_608f,
                    _ => BinaryPrimitives.ReadInt32LittleEndian(ch) / 2_147_483_648f,
                };
            }

            output[i] = sum / channels;
        }

        return output;
    }

    /// <summary>RMS level in 0..1 for the recorder's meter (-50 dBFS .. 0 dBFS).</summary>
    public static float MeterLevel(ReadOnlySpan<float> samples)
    {
        if (samples.IsEmpty) return 0f;
        double sum = 0;
        foreach (var s in samples) sum += s * s;
        var rms = Math.Sqrt(sum / samples.Length);
        var db = 20 * Math.Log10(Math.Max(rms, 1e-6));
        return (float)Math.Clamp((db + 50) / 50, 0, 1);
    }

    public static double DurationSecs(int samples, int sampleRate = TargetSampleRate) => (double)samples / sampleRate;

    public static float[] Resample(float[] input, int inputRate, int outputRate) =>
        new Resampler(inputRate, outputRate).Process(input);
}

/// <summary>Streaming linear-interpolation resampler with a boxcar anti-alias filter for down-sampling.</summary>
public sealed class Resampler
{
    private readonly double _ratio;
    private readonly float[] _filter;
    private double _position;
    private float _previous;
    private int _filterPos;

    public Resampler(int inputRate, int outputRate)
    {
        _ratio = (double)inputRate / outputRate;
        _filter = new float[Math.Max(1, (int)Math.Floor(_ratio))];
    }

    public float[] Process(ReadOnlySpan<float> input)
    {
        if (Math.Abs(_ratio - 1.0) < double.Epsilon) return input.ToArray();

        float[] filtered;
        if (_filter.Length > 1)
        {
            filtered = new float[input.Length];
            for (var i = 0; i < input.Length; i++)
            {
                _filter[_filterPos] = input[i];
                _filterPos = (_filterPos + 1) % _filter.Length;
                var sum = 0f;
                foreach (var f in _filter) sum += f;
                filtered[i] = sum / _filter.Length;
            }
        }
        else
        {
            filtered = input.ToArray();
        }

        var output = new List<float>((int)(filtered.Length / _ratio) + 1);
        // `_position` is measured relative to `_previous` (index -1 of this block).
        while (_position < filtered.Length)
        {
            var idx = (int)Math.Floor(_position);
            var frac = (float)(_position - idx);
            var a = idx == 0 ? _previous : filtered[idx - 1];
            var b = filtered[idx];
            output.Add(a + ((b - a) * frac));
            _position += _ratio;
        }

        _position -= filtered.Length;
        if (filtered.Length > 0) _previous = filtered[^1];
        return [.. output];
    }
}

public static class Wav
{
    /// <summary>16-bit mono PCM WAV.</summary>
    public static byte[] EncodeI16(ReadOnlySpan<float> samples, int sampleRate)
    {
        var dataLen = samples.Length * 2;
        var output = new byte[44 + dataLen];
        var span = output.AsSpan();
        "RIFF"u8.CopyTo(span);
        BinaryPrimitives.WriteUInt32LittleEndian(span[4..], (uint)(36 + dataLen));
        "WAVE"u8.CopyTo(span[8..]);
        "fmt "u8.CopyTo(span[12..]);
        BinaryPrimitives.WriteUInt32LittleEndian(span[16..], 16);
        BinaryPrimitives.WriteUInt16LittleEndian(span[20..], 1); // PCM
        BinaryPrimitives.WriteUInt16LittleEndian(span[22..], 1); // mono
        BinaryPrimitives.WriteUInt32LittleEndian(span[24..], (uint)sampleRate);
        BinaryPrimitives.WriteUInt32LittleEndian(span[28..], (uint)(sampleRate * 2));
        BinaryPrimitives.WriteUInt16LittleEndian(span[32..], 2);
        BinaryPrimitives.WriteUInt16LittleEndian(span[34..], 16);
        "data"u8.CopyTo(span[36..]);
        BinaryPrimitives.WriteUInt32LittleEndian(span[40..], (uint)dataLen);
        for (var i = 0; i < samples.Length; i++)
        {
            var v = (short)Math.Round(Math.Clamp(samples[i], -1f, 1f) * 32767f);
            BinaryPrimitives.WriteInt16LittleEndian(span[(44 + (i * 2))..], v);
        }

        return output;
    }

    /// <summary>Decodes PCM8/16/24/32 and float32 WAV files (including WAVE_FORMAT_EXTENSIBLE) to mono floats.</summary>
    public static DecodedWav Decode(ReadOnlySpan<byte> bytes)
    {
        if (bytes.Length < 12 || !bytes[..4].SequenceEqual("RIFF"u8) || !bytes[8..12].SequenceEqual("WAVE"u8))
        {
            throw new InvalidDataException("not a RIFF/WAVE file");
        }

        var pos = 12;
        (ushort Tag, ushort Channels, int Rate, ushort Bits)? fmt = null;
        while (pos + 8 <= bytes.Length)
        {
            var id = bytes.Slice(pos, 4);
            var len = (int)BinaryPrimitives.ReadUInt32LittleEndian(bytes[(pos + 4)..]);
            var bodyStart = pos + 8;
            var bodyEnd = (int)Math.Min((long)bodyStart + len, bytes.Length);
            var body = bytes[bodyStart..bodyEnd];

            if (id.SequenceEqual("fmt "u8) && body.Length >= 16)
            {
                var tag = BinaryPrimitives.ReadUInt16LittleEndian(body);
                var channels = BinaryPrimitives.ReadUInt16LittleEndian(body[2..]);
                var rate = (int)BinaryPrimitives.ReadUInt32LittleEndian(body[4..]);
                var bits = BinaryPrimitives.ReadUInt16LittleEndian(body[14..]);
                if (tag == 0xFFFE && body.Length >= 26)
                {
                    tag = BinaryPrimitives.ReadUInt16LittleEndian(body[24..]);
                }

                fmt = (tag, channels, rate, bits);
            }
            else if (id.SequenceEqual("data"u8))
            {
                var (tag, channels, rate, bits) = fmt ?? throw new InvalidDataException("data chunk before fmt chunk");
                var ch = Math.Max(1, (int)channels);
                float[] samples;
                switch (tag, bits)
                {
                    case (1, 8):
                        samples = new float[body.Length / ch];
                        for (var i = 0; i < samples.Length; i++)
                        {
                            var sum = 0f;
                            for (var c = 0; c < ch; c++) sum += (body[(i * ch) + c] - 128f) / 128f;
                            samples[i] = sum / ch;
                        }

                        break;
                    case (1, 16): samples = AudioConvert.DownmixToMono(body, SampleFormat.I16, ch); break;
                    case (1, 24): samples = AudioConvert.DownmixToMono(body, SampleFormat.I24, ch); break;
                    case (1, 32): samples = AudioConvert.DownmixToMono(body, SampleFormat.I32, ch); break;
                    case (3, 32): samples = AudioConvert.DownmixToMono(body, SampleFormat.F32, ch); break;
                    default:
                        throw new InvalidDataException($"unsupported WAV encoding (format {tag}, {bits} bits)");
                }

                return new DecodedWav(rate, samples);
            }

            pos = bodyStart + len + (len & 1);
        }

        throw new InvalidDataException("WAV file has no data chunk");
    }

    /// <summary>Decodes a WAV file and resamples it to 16 kHz mono.</summary>
    public static float[] Load16k(ReadOnlySpan<byte> bytes)
    {
        var wav = Decode(bytes);
        return AudioConvert.Resample(wav.Samples, wav.SampleRate, AudioConvert.TargetSampleRate);
    }
}
