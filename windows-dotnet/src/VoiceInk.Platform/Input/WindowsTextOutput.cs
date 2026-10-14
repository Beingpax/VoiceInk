using System.Diagnostics;
using VoiceInk.Core;
using VoiceInk.Core.Config;
using VoiceInk.Core.Dictation;

namespace VoiceInk.Platform.Input;

/// <summary>Inserts text into the focused app (paste with clipboard restore, typing, custom command) and copies selections.</summary>
public sealed class WindowsTextOutput : ITextOutput
{
    private static readonly TimeSpan PrePasteDelay = TimeSpan.FromMilliseconds(60);
    private static readonly TimeSpan MinRestoreDelay = TimeSpan.FromMilliseconds(250);

    public string? ClipboardText() => ClipboardApi.GetText();

    public Task<string?> CopySelectionAsync() => Task.Run(CopySelection);

    public Task DeliverAsync(Delivery delivery, OutputSettings settings, nint target, CancellationToken ct) =>
        Task.Run(() => Deliver(delivery, settings), ct);

    private static void Deliver(Delivery delivery, OutputSettings settings)
    {
        if (delivery.Output == OutputMode.CustomCommand)
        {
            RunCustomCommand(delivery);
            return;
        }

        PasteText(delivery.Text, settings, delivery.SendKey);
    }

    private static void PressSendKey(SendKey key)
    {
        switch (key)
        {
            case SendKey.Enter: Keyboard.Tap(Keyboard.VK_RETURN); break;
            case SendKey.ShiftEnter: Keyboard.Chord(Keyboard.VK_SHIFT, Keyboard.VK_RETURN); break;
            case SendKey.CtrlEnter: Keyboard.Chord(Keyboard.VK_CONTROL, Keyboard.VK_RETURN); break;
        }
    }

    private static void PasteText(string text, OutputSettings settings, SendKey sendKey)
    {
        if (settings.AppendSpace && !char.IsWhiteSpace(text[^1])) text += " ";
        Keyboard.ReleaseHeldModifiers();

        if (settings.Method == PasteMethod.Type)
        {
            Thread.Sleep(PrePasteDelay);
            if (!Keyboard.TypeText(text))
            {
                throw new OutputException("Windows blocked simulated typing (is the target app running as administrator?)");
            }

            if (sendKey != SendKey.None)
            {
                Thread.Sleep(80);
                PressSendKey(sendKey);
            }

            return;
        }

        var snapshot = settings.RestoreClipboard ? ClipboardApi.Snapshot.Capture() : null;
        uint sequence;
        try
        {
            sequence = ClipboardApi.SetText(text, settings.RestoreClipboard);
        }
        catch (IOException e)
        {
            throw new OutputException(e.Message);
        }

        Thread.Sleep(PrePasteDelay);
        var posted = settings.Method == PasteMethod.ShiftInsert
            ? Keyboard.Chord(Keyboard.VK_SHIFT, Keyboard.VK_INSERT)
            : Keyboard.Chord(Keyboard.VK_CONTROL, Keyboard.VK_V);

        if (posted && sendKey != SendKey.None)
        {
            Thread.Sleep(150);
            PressSendKey(sendKey);
        }

        if (snapshot is not null)
        {
            var delay = TimeSpan.FromMilliseconds(settings.ClipboardRestoreDelayMs);
            Thread.Sleep(delay > MinRestoreDelay ? delay : MinRestoreDelay);
            // Only restore if nobody (user or app) changed the clipboard since our paste.
            if (ClipboardApi.SequenceNumber == sequence)
            {
                try { snapshot.Restore(); } catch (IOException e) { AppLog.Warn($"clipboard restore failed: {e.Message}"); }
            }
        }

        if (!posted)
        {
            throw new OutputException(
                "Windows blocked the paste keystroke (is the target app running as administrator?). The text is on the clipboard.");
        }
    }

    private static string? CopySelection()
    {
        var snapshot = ClipboardApi.Snapshot.Capture();
        var before = ClipboardApi.SequenceNumber;
        // A held Shift/Alt from a shortcut like Ctrl+Shift+Space would turn Ctrl+C into another command
        // (Ctrl+Shift+C opens DevTools in browsers). Always send a complete chord: relying on a physically held
        // Ctrl races with the user releasing the shortcut.
        Keyboard.ReleaseHeldModifiers();
        Keyboard.Chord(Keyboard.VK_CONTROL, Keyboard.VK_C);

        var deadline = DateTime.UtcNow.AddMilliseconds(250);
        while (ClipboardApi.SequenceNumber == before && DateTime.UtcNow < deadline) Thread.Sleep(10);
        if (ClipboardApi.SequenceNumber == before) return null; // Nothing selected (or the app ignored Ctrl+C).

        var selected = ClipboardApi.GetText();
        try { snapshot.Restore(); } catch (IOException) { }
        return string.IsNullOrWhiteSpace(selected) ? null : selected;
    }

    private static void RunCustomCommand(Delivery delivery)
    {
        if (string.IsNullOrWhiteSpace(delivery.CustomCommand))
        {
            throw new OutputException("No command configured for this mode");
        }

        var info = new ProcessStartInfo("cmd.exe")
        {
            ArgumentList = { "/D", "/S", "/C", delivery.CustomCommand },
            RedirectStandardInput = true,
            RedirectStandardError = true,
            RedirectStandardOutput = true,
            CreateNoWindow = true,
            UseShellExecute = false,
        };
        info.Environment["VOICEINK_TRANSCRIPT"] = delivery.Text;

        using var process = Process.Start(info) ?? throw new OutputException("could not start the command");
        process.StandardInput.Write(delivery.Text);
        process.StandardInput.Close();
        var error = process.StandardError.ReadToEndAsync();
        _ = process.StandardOutput.ReadToEndAsync();
        if (!process.WaitForExit(TimeSpan.FromSeconds(10)))
        {
            process.Kill(entireProcessTree: true);
            throw new OutputException("Custom command timed out after 10 seconds");
        }

        if (process.ExitCode != 0)
        {
            throw new OutputException($"Custom command failed (exit code {process.ExitCode}): {error.Result.Trim()}");
        }

        if (delivery.SendKey != SendKey.None)
        {
            Thread.Sleep(150);
            PressSendKey(delivery.SendKey);
        }
    }
}
