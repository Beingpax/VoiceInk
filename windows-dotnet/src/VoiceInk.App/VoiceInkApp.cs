using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using VoiceInk.App.Views;
using VoiceInk.Core;
using VoiceInk.Core.Dictation;
using VoiceInk.Platform.Shell;

namespace VoiceInk.App;

/// <summary>The WinUI application: owns the services, the tray icon, the recorder pill and the main window.</summary>
internal sealed class VoiceInkApp : Application
{
    private readonly SingleInstance _instance;
    private readonly AppServices _services;
    private readonly OverlayWindow _overlay;
    private MainWindow? _main;

    public VoiceInkApp(SingleInstance instance, string? startPage)
    {
        _instance = instance;
        Resources.MergedDictionaries.Add(new XamlControlsResources());
        UnhandledException += (_, e) =>
        {
            AppLog.Error("unhandled exception", e.Exception);
            e.Handled = true;
        };

        var firstRun = !File.Exists(VoiceInk.Core.Config.AppPaths.ConfigPath);
        _services = new AppServices(Microsoft.UI.Dispatching.DispatcherQueue.GetForCurrentThread());
        _overlay = new OverlayWindow(() => _services.Cfg.Overlay, _services.Dictation.Toggle);

        var menu = new TrayMenu(_services, Show, Quit);
        _services.Tray.MenuProvider = menu.Build;
        _services.Tray.Clicked += () => _services.RunOnUi(() => Show("dashboard"));
        _services.Dictation.StatusChanged += status => _services.RunOnUi(() => OnStatus(status));
        _instance.Listen(command => _services.RunOnUi(() => Show(command)));
        OnStatus(_services.Dictation.Status);
        AppLog.Info($"VoiceInk for Windows {AppInfo.Version} started");

        if (startPage is not null || firstRun) Show(startPage ?? "dashboard");
    }

    private void OnStatus(DictationStatus status)
    {
        _overlay.Apply(status);
        var (state, tip) = status.Phase switch
        {
            Phase.Recording => (TrayState.Recording, "Recording…"),
            Phase.Transcribing or Phase.Enhancing => (TrayState.Busy, "Processing…"),
            _ => (TrayState.Idle, "Ready"),
        };
        _services.Tray.SetState(state, $"VoiceInk — {tip}\n{_services.Cfg.Hotkeys.Record}");
    }

    private void Show(string page)
    {
        _main ??= new MainWindow(_services);
        _main.Navigate(page is "settings" ? "general" : page);
        _main.Present();
    }

    private void Quit()
    {
        _services.RunOnUi(() =>
        {
            _services.Dictation.CancelAll();
            _main?.ForceClose();
            _overlay.Close();
            _services.Dispose();
            _instance.Dispose();
            Exit();
        });
    }
}
