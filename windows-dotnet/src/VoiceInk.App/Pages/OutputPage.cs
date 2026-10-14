using Microsoft.UI.Xaml;
using VoiceInk.App.Ui;
using VoiceInk.Core.Config;
using VoiceInk.Platform.Audio;

namespace VoiceInk.App.Pages;

internal static class OutputPage
{
    public static UIElement Build(AppServices s)
    {
        var o = s.Cfg.Output;
        var a = s.Cfg.Audio;
        var h = s.Cfg.History;

        var devices = new List<(string? Value, string Label)> { (null, "System default") };
        try
        {
            devices.AddRange(WasapiAudioCapture.ListInputDevices().Select(d => ((string?)d.Name, d.Name)));
        }
        catch (Exception e) when (e is System.Runtime.InteropServices.COMException or InvalidOperationException)
        {
            // No audio service: only the default entry is offered.
        }

        return Fluent.Page("Output & Audio",
            Fluent.Section("Inserting text",
                Fluent.Row("Insert text with", "Switch to Shift+Insert or typing if an app ignores Ctrl+V (some terminals).", Fluent.Combo(
                    [(PasteMethod.CtrlV, "Ctrl+V (clipboard)"), (PasteMethod.ShiftInsert, "Shift+Insert (clipboard)"), (PasteMethod.Type, "Simulated typing")],
                    o.Method, v => s.Update(c => c.Output.Method = v), 240)),
                Fluent.Row("Restore clipboard", "Puts your previous clipboard (all formats) back after pasting. The text never appears in Win+V history.",
                    Fluent.Toggle(o.RestoreClipboard, v => s.Update(c => c.Output.RestoreClipboard = v))),
                Fluent.Row("Restore delay", "Milliseconds to wait before restoring.", Fluent.Number(o.ClipboardRestoreDelayMs, 250, 5000, v => s.Update(c => c.Output.ClipboardRestoreDelayMs = (ulong)v), 50)),
                Fluent.Row("Press after inserting", "\"Finish & Send\" for chat apps.", Fluent.Combo(
                    [(SendKey.None, "Nothing"), (SendKey.Enter, "Enter"), (SendKey.ShiftEnter, "Shift+Enter"), (SendKey.CtrlEnter, "Ctrl+Enter")],
                    o.SendKey, v => s.Update(c => c.Output.SendKey = v), 200)),
                Fluent.Row("Add a trailing space", "So consecutive dictations don't run together.", Fluent.Toggle(o.AppendSpace, v => s.Update(c => c.Output.AppendSpace = v)))),
            Fluent.Section("Microphone",
                Fluent.Row("Input device", null, Fluent.Combo([.. devices], a.InputDevice, v => s.Update(c => c.Audio.InputDevice = v), 320)),
                Fluent.Row("Play start/stop sounds", null, Fluent.Toggle(a.PlaySounds, v => s.Update(c => c.Audio.PlaySounds = v))),
                Fluent.Row("Mute system audio while recording", "Music and videos are muted, then restored.", Fluent.Toggle(a.MuteSystemAudio, v => s.Update(c => c.Audio.MuteSystemAudio = v))),
                Fluent.Row("Minimum recording", "Shorter recordings are discarded (ms).", Fluent.Number(a.MinRecordingMs, 0, 3000, v => s.Update(c => c.Audio.MinRecordingMs = (ulong)v), 50))),
            Fluent.Section("History",
                Fluent.Row("Keep history", "Powers the dashboard and “Paste last transcription”.", Fluent.Toggle(h.Enabled, v => s.Update(c => c.History.Enabled = v))),
                Fluent.Row("Save audio", "Stores each recording as a WAV next to the history.", Fluent.Toggle(h.SaveAudio, v => s.Update(c => c.History.SaveAudio = v))),
                Fluent.Row("Maximum entries", "0 keeps everything.", Fluent.Number(h.MaxEntries, 0, 100000, v => s.Update(c => c.History.MaxEntries = (int)v), 100))));
    }
}
