using System.Reflection;
using System.Runtime.InteropServices;
using NAudio.CoreAudioApi;
using VoiceInk.Core.Dictation;
using static VoiceInk.Platform.Native;

namespace VoiceInk.Platform.Audio;

/// <summary>Start/stop/cancel cues (the original VoiceInk sounds) through <c>PlaySound</c>.</summary>
public sealed class WindowsSoundPlayer : ISoundPlayer
{
    // PlaySound(SND_MEMORY | SND_ASYNC) reads the buffer while playing, so it must stay valid and unmoved.
    private static readonly Dictionary<Cue, nint> Buffers = LoadBuffers();

    private static Dictionary<Cue, nint> LoadBuffers()
    {
        var assembly = Assembly.GetExecutingAssembly();
        var map = new Dictionary<Cue, nint>();
        foreach (var (cue, name) in new[] { (Cue.Start, "start"), (Cue.Stop, "stop"), (Cue.Cancel, "cancel") })
        {
            using var stream = assembly.GetManifestResourceStream($"Sounds.{name}.wav");
            if (stream is null) continue;
            var bytes = new byte[stream.Length];
            stream.ReadExactly(bytes);
            var ptr = Marshal.AllocHGlobal(bytes.Length);
            Marshal.Copy(bytes, 0, ptr, bytes.Length);
            map[cue] = ptr;
        }

        return map;
    }

    public void Play(Cue cue, string? customFile)
    {
        if (!string.IsNullOrWhiteSpace(customFile) && File.Exists(customFile))
        {
            var path = Marshal.StringToHGlobalUni(customFile);
            try { PlaySound(path, 0, SND_FILENAME | SND_ASYNC | SND_NODEFAULT); }
            finally { /* PlaySound copies the file name before returning for SND_FILENAME. */ Marshal.FreeHGlobal(path); }
            return;
        }

        if (Buffers.TryGetValue(cue, out var buffer)) PlaySound(buffer, 0, SND_MEMORY | SND_ASYNC | SND_NODEFAULT);
    }
}

/// <summary>Mutes the default playback device while recording and unmutes it afterwards.</summary>
public sealed class WindowsSystemMuter : ISystemMuter
{
    public IDisposable? Mute()
    {
        try
        {
            using var enumerator = new MMDeviceEnumerator();
            var device = enumerator.GetDefaultAudioEndpoint(DataFlow.Render, Role.Console);
            if (device.AudioEndpointVolume.Mute) return null;
            device.AudioEndpointVolume.Mute = true;
            return new Restore(device);
        }
        catch (COMException)
        {
            return null;
        }
    }

    private sealed class Restore(MMDevice device) : IDisposable
    {
        public void Dispose()
        {
            try { device.AudioEndpointVolume.Mute = false; }
            catch (COMException) { }
            finally { device.Dispose(); }
        }
    }
}
