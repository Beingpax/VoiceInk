using VoiceInk.Core.Dictation;
using VoiceInk.Platform.Shell;

namespace VoiceInk.App;

/// <summary>Builds the notification-area menu from the current app state.</summary>
internal sealed class TrayMenu(AppServices services, Action<string> showWindow, Action quit)
{
    public IReadOnlyList<TrayMenuItem> Build()
    {
        var cfg = services.Cfg;
        var phase = services.Dictation.Status.Phase;
        var toggle = phase switch
        {
            Phase.Idle => "Start recording",
            Phase.Recording => "Stop recording",
            _ => "Cancel processing",
        };

        var items = new List<TrayMenuItem>
        {
            new($"VoiceInk {AppInfo.Version}", Enabled: false),
            new($"Shortcut: {cfg.Hotkeys.Record}", Enabled: false),
        };
        if (cfg.Command.Enabled) items.Add(new TrayMenuItem($"Command Mode: {cfg.Command.Hotkey}", Enabled: false));
        items.AddRange(
        [
            TrayMenuItem.Separator,
            new("Dashboard…", () => showWindow("dashboard")),
            new("Settings…", () => showWindow("general")),
            TrayMenuItem.Separator,
            new(toggle, services.Dictation.Toggle),
            new("Paste last transcription", services.Dictation.PasteLast),
            TrayMenuItem.Separator,
            new("AI Enhancement", () => services.Update(c => c.Enhancement.Enabled = !c.Enhancement.Enabled), Checked: cfg.Enhancement.Enabled),
            new("Launch at login", ToggleAutostart, Checked: Autostart.IsEnabled()),
            new("Reload settings file", () => services.Config.Reload(force: true)),
            TrayMenuItem.Separator,
            new("Quit VoiceInk", quit),
        ]);
        return items;
    }

    private void ToggleAutostart()
    {
        var enable = !Autostart.IsEnabled();
        Autostart.SetEnabled(enable);
        services.Update(c => c.StartWithWindows = enable);
    }
}
