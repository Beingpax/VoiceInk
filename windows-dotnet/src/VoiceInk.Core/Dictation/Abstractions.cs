using VoiceInk.Core.Config;

namespace VoiceInk.Core.Dictation;

public enum NoticeKind { Info, Warning, Error }

public enum Cue { Start, Stop, Cancel }

public enum TriggerKind { Dictation, Command }

public enum HotkeyEventKind { Down, Up, Abort, Cancel, PasteLast }

public readonly record struct HotkeyEvent(HotkeyEventKind Kind, TriggerKind Trigger = TriggerKind.Dictation);

/// <summary>The window that will receive the text, plus what modes need to know about it.</summary>
public sealed record ForegroundTarget(nint Handle, ForegroundInfo Info);

/// <summary>A running microphone capture.</summary>
public interface IRecordingSession : IDisposable
{
    TimeSpan Elapsed { get; }

    /// <summary>Current input level in 0..1 for the meter.</summary>
    float Level { get; }

    /// <summary>Stops capturing and returns 16 kHz mono samples.</summary>
    float[] Finish();

    void Cancel();
}

public interface IAudioCapture
{
    IRecordingSession Start(string? deviceName);
}

public interface IForeground
{
    /// <summary>The focused window, or the last external window while VoiceInk or the shell has focus.</summary>
    ForegroundTarget Capture();

    void Restore(nint handle);
}

/// <summary>Puts finished text into the target application and reads context from it.</summary>
public interface ITextOutput
{
    /// <exception cref="OutputException">Delivery failed; the message is shown to the user.</exception>
    Task DeliverAsync(Delivery delivery, OutputSettings settings, nint target, CancellationToken ct);

    /// <summary>Copies the current selection (Ctrl+C) and restores the clipboard. Null when nothing is selected.</summary>
    Task<string?> CopySelectionAsync();

    string? ClipboardText();
}

public sealed class OutputException(string message) : Exception(message);

public interface ISoundPlayer
{
    void Play(Cue cue, string? customFile);
}

public interface ISystemMuter
{
    /// <summary>Mutes system output; disposing the result restores it. Null when already muted.</summary>
    IDisposable? Mute();
}

public interface IHotkeyService
{
    event Action<HotkeyEvent>? Triggered;

    /// <summary>(Re)installs the shortcuts and returns human-readable problems with any of them.</summary>
    IReadOnlyList<string> Apply(HotkeySettings settings, string? commandHotkey);

    /// <summary>While active, the cancel key is swallowed and reported.</summary>
    void SetActive(bool active);
}

public interface INotifier
{
    void Notify(string title, string message, NoticeKind kind);
}

public interface IHistoryStore
{
    void Append(HistoryEntry entry, int maxEntries);
    string? LastText();
}

public interface IConfigStore
{
    AppConfig Current { get; }

    /// <summary>Re-reads the file when it changed (or always with <paramref name="force"/>). True when the config changed.</summary>
    bool Reload(bool force = false);

    void Save();

    event Action? Changed;
}
