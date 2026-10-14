using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using VoiceInk.App.Ui;
using VoiceInk.Core.Config;
using VoiceInk.Platform.Shell;

namespace VoiceInk.App.Pages;

internal static class GeneralPage
{
    public static UIElement Build(AppServices s)
    {
        var cfg = s.Cfg;
        return Fluent.Page("General",
            Fluent.Section("Shortcuts",
                Fluent.Row("Record shortcut", "Examples: RightCtrl, F9, Ctrl+Shift+Space, Mouse4", HotkeyBox(s, cfg.Hotkeys.Record, v => s.Update(c => c.Hotkeys.Record = v))),
                Fluent.Row("Behavior", "Hybrid: tap to toggle, hold to talk.", Fluent.Combo(
                    [(HotkeyMode.Hybrid, "Tap to toggle, hold to talk"), (HotkeyMode.Toggle, "Toggle"), (HotkeyMode.PushToTalk, "Push to talk")],
                    cfg.Hotkeys.Mode, v => s.Update(c => c.Hotkeys.Mode = v))),
                Fluent.Row("Hold threshold", "Holding the key longer than this (ms) counts as push-to-talk.",
                    Fluent.Number(cfg.Hotkeys.HybridThresholdMs, 100, 3000, v => s.Update(c => c.Hotkeys.HybridThresholdMs = (ulong)v), 50)),
                Fluent.Row("Cancel", "Cancels a recording or a running transcription.", HotkeyBox(s, cfg.Hotkeys.Cancel, v => s.Update(c => c.Hotkeys.Cancel = v))),
                Fluent.Row("Paste last transcription", "Leave empty to disable.", HotkeyBox(s, cfg.Hotkeys.PasteLast ?? "", v => s.Update(c => c.Hotkeys.PasteLast = v.Length == 0 ? null : v)))),
            Fluent.Section("Command Mode",
                Fluent.Row("Enable Command Mode", "Select text, say what to do with it (\"make this more formal\"). Nothing selected: it writes new text.",
                    Fluent.Toggle(cfg.Command.Enabled, v => s.Update(c => c.Command.Enabled = v))),
                Fluent.Row("Command shortcut", null, HotkeyBox(s, cfg.Command.Hotkey, v => s.Update(c => c.Command.Hotkey = v)))),
            Fluent.Section("Appearance",
                Fluent.Row("Theme", null, Fluent.Combo(
                    [(AppTheme.System, "Use system setting"), (AppTheme.Light, "Light"), (AppTheme.Dark, "Dark")],
                    cfg.Theme, v => s.Update(c => c.Theme = v), 200)),
                Fluent.Row("Recorder pill", "Where the small recording indicator appears.", Fluent.Combo(
                    [(OverlayPosition.BottomCenter, "Bottom center"), (OverlayPosition.TopCenter, "Top center"), (OverlayPosition.Hidden, "Hidden")],
                    cfg.Overlay, v => s.Update(c => c.Overlay = v), 200))),
            Fluent.Section("System",
                Fluent.Row("Launch at login", null, Fluent.Toggle(Autostart.IsEnabled(), v =>
                {
                    Autostart.SetEnabled(v);
                    s.Update(c => c.StartWithWindows = v);
                })),
                Fluent.Row("Settings file", AppPaths.ConfigPath, Fluent.Button("Open folder", () => OpenFolder(AppPaths.DataDir), glyph: ""))));
    }

    /// <summary>Text box that rejects shortcuts the parser does not understand and says why.</summary>
    private static UIElement HotkeyBox(AppServices services, string value, Action<string> set)
    {
        var error = Fluent.Caption("");
        error.Foreground = new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.Colors.IndianRed);
        error.HorizontalAlignment = HorizontalAlignment.Right;
        var box = Fluent.Text(value, text =>
        {
            text = text.Trim();
            if (text.Length > 0 && !HotkeyParser.TryParse(text, out _, out var message))
            {
                error.Text = message;
                return;
            }

            error.Text = "";
            set(text);
        }, "RightCtrl", 220);
        return new StackPanel { Spacing = 4, Children = { box, error } };
    }

    private static void OpenFolder(string path)
    {
        Directory.CreateDirectory(path);
        System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(path) { UseShellExecute = true });
    }
}
