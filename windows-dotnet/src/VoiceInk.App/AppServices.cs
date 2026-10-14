using Microsoft.UI.Dispatching;
using VoiceInk.Core;
using VoiceInk.Core.Config;
using VoiceInk.Core.Dictation;
using VoiceInk.Platform.Audio;
using VoiceInk.Platform.Hotkeys;
using VoiceInk.Platform.Input;
using VoiceInk.Platform.Shell;

namespace VoiceInk.App;

/// <summary>Composition root: builds the object graph once and exposes what the UI needs.</summary>
internal sealed class AppServices : IDisposable
{
    private readonly WindowsForeground _foreground;

    public AppServices(DispatcherQueue ui)
    {
        UiQueue = ui;
        Credentials.Protector = new DpapiProtector();
        Config = new FileConfigStore();
        Tray = new TrayIcon();
        _foreground = new WindowsForeground();
        Hotkeys = new WindowsHotkeyService();
        Dictation = new DictationController(
            Config,
            new WasapiAudioCapture(),
            _foreground,
            new WindowsTextOutput(),
            new WindowsSoundPlayer(),
            new WindowsSystemMuter(),
            new FileHistoryStore(),
            Tray);

        Hotkeys.Triggered += Dictation.HandleHotkey;
        Dictation.StatusChanged += status => Hotkeys.SetActive(status.Phase != Phase.Idle);
        Config.Changed += ApplyHotkeys;
        ApplyHotkeys();
    }

    public DispatcherQueue UiQueue { get; }
    public IConfigStore Config { get; }
    public TrayIcon Tray { get; }
    public WindowsHotkeyService Hotkeys { get; }
    public DictationController Dictation { get; }

    public AppConfig Cfg => Config.Current;

    /// <summary>Changes the settings and persists them; the hotkeys are re-applied through <see cref="IConfigStore.Changed"/>.</summary>
    public void Update(Action<AppConfig> change)
    {
        change(Cfg);
        Config.Save();
    }

    /// <summary>Runs on the UI thread, whichever thread calls.</summary>
    public void RunOnUi(Action action)
    {
        if (!UiQueue.TryEnqueue(() => action())) AppLog.Warn("UI queue is shut down; dropped a UI update");
    }

    private void ApplyHotkeys()
    {
        var command = Cfg.Command.Enabled ? Cfg.Command.Hotkey : null;
        var problems = Hotkeys.Apply(Cfg.Hotkeys, command);
        if (problems.Count > 0) Tray.Notify("Hotkey problem", string.Join("\n", problems), NoticeKind.Warning);
    }

    public void Dispose()
    {
        Hotkeys.Dispose();
        _foreground.Dispose();
        Tray.Dispose();
    }
}
