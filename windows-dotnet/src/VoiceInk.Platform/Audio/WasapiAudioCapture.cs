using NAudio.CoreAudioApi;
using NAudio.Wave;
using VoiceInk.Core.Audio;
using VoiceInk.Core.Dictation;

namespace VoiceInk.Platform.Audio;

/// <summary>WASAPI shared-mode microphone capture. Any mix format is downmixed to mono and resampled to 16 kHz.</summary>
public sealed class WasapiAudioCapture : IAudioCapture
{
    public IRecordingSession Start(string? deviceName) => new Session(FindDevice(deviceName));

    /// <summary>Active microphones; the flag marks the system default.</summary>
    public static IReadOnlyList<(string Name, bool IsDefault)> ListInputDevices()
    {
        using var enumerator = new MMDeviceEnumerator();
        var defaultId = DefaultCaptureId(enumerator);
        return enumerator.EnumerateAudioEndPoints(DataFlow.Capture, DeviceState.Active)
            .Select(d => (d.FriendlyName, d.ID == defaultId))
            .ToList();
    }

    private static string? DefaultCaptureId(MMDeviceEnumerator enumerator)
    {
        try { return enumerator.GetDefaultAudioEndpoint(DataFlow.Capture, Role.Console).ID; }
        catch (System.Runtime.InteropServices.COMException) { return null; }
    }

    private static MMDevice FindDevice(string? name)
    {
        using var enumerator = new MMDeviceEnumerator();
        if (!string.IsNullOrWhiteSpace(name))
        {
            var match = enumerator.EnumerateAudioEndPoints(DataFlow.Capture, DeviceState.Active)
                .FirstOrDefault(d => d.FriendlyName.Contains(name, StringComparison.OrdinalIgnoreCase));
            if (match is not null) return match;
        }

        try
        {
            return enumerator.GetDefaultAudioEndpoint(DataFlow.Capture, Role.Console);
        }
        catch (System.Runtime.InteropServices.COMException)
        {
            throw new InvalidOperationException("No microphone found. Check Settings › Privacy & security › Microphone.");
        }
    }

    private sealed class Session : IRecordingSession
    {
        private static readonly Guid IeeeFloatSubFormat = new("00000003-0000-0010-8000-00aa00389b71");

        private readonly WasapiRecorder _capture;
        private readonly Resampler _resampler;
        private readonly SampleFormat _format;
        private readonly int _channels;
        private readonly List<float> _samples = [];
        private readonly object _gate = new();
        private readonly System.Diagnostics.Stopwatch _clock = System.Diagnostics.Stopwatch.StartNew();
        private float _level;
        private bool _stopped;

        public Session(MMDevice device)
        {
            _capture = new WasapiRecorderBuilder().WithDevice(device).Build();
            var wf = _capture.WaveFormat;
            _channels = wf.Channels;
            _resampler = new Resampler(wf.SampleRate, AudioConvert.TargetSampleRate);
            _format = (wf.Encoding, wf.BitsPerSample) switch
            {
                (WaveFormatEncoding.IeeeFloat, 32) => SampleFormat.F32,
                (WaveFormatEncoding.Extensible, 32) when wf is WaveFormatExtensible { SubFormat: var g } && g == IeeeFloatSubFormat
                    => SampleFormat.F32,
                (_, 16) => SampleFormat.I16,
                (_, 24) => SampleFormat.I24,
                (_, 32) => SampleFormat.I32,
                _ => throw new NotSupportedException($"unsupported microphone format {wf}"),
            };
            _capture.DataAvailable += (buffer, flags, devicePosition, qpcPosition) => OnData(buffer);
            _capture.StartRecording();
        }

        public TimeSpan Elapsed => _clock.Elapsed;

        public float Level
        {
            get { lock (_gate) return _level; }
        }

        private void OnData(ReadOnlySpan<byte> buffer)
        {
            var mono = AudioConvert.DownmixToMono(buffer, _format, _channels);
            var level = AudioConvert.MeterLevel(mono);
            var resampled = _resampler.Process(mono);
            lock (_gate)
            {
                if (_stopped) return;
                _samples.AddRange(resampled);
                // Smooth the meter so the pill doesn't flicker.
                _level = Math.Max(level, _level * 0.8f);
            }
        }

        private void StopCapture()
        {
            lock (_gate) _stopped = true;
            try { _capture.StopRecording(); } catch (InvalidOperationException) { }
        }

        public float[] Finish()
        {
            StopCapture();
            lock (_gate) return [.. _samples];
        }

        public void Cancel() => StopCapture();

        public void Dispose()
        {
            StopCapture();
            _capture.Dispose();
        }
    }
}
