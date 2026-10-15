using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using VoiceInk.App.Views;
using VoiceInk.Core;
using VoiceInk.Core.Dictation;
using VoiceInk.Platform.Shell;

namespace VoiceInk.App;

/// <summary>The WinUI application: owns the services, the tray icon, the recorder pill and the main window.</summary>
internal sealed class VoiceInkApp : Application, Microsoft.UI.Xaml.Markup.IXamlMetadataProvider
{
    private readonly Microsoft.UI.Xaml.XamlTypeInfo.XamlControlsXamlMetaDataProvider _metadata = new();
    public Microsoft.UI.Xaml.Markup.IXamlType? GetXamlType(Type type) => _metadata.GetXamlType(type);
    public Microsoft.UI.Xaml.Markup.IXamlType? GetXamlType(string fullName) => _metadata.GetXamlType(fullName);
    public Microsoft.UI.Xaml.Markup.XmlnsDefinition[] GetXmlnsDefinitions() => _metadata.GetXmlnsDefinitions();

    private readonly SingleInstance _instance;
    private readonly string? _startPage;
    private AppServices _services = null!;
    private OverlayWindow _overlay = null!;
    private MainWindow? _main;

    public VoiceInkApp(SingleInstance instance, string? startPage)
    {
        _instance = instance;
        _startPage = startPage;
        UnhandledException += (_, e) =>
        {
            AppLog.Error("unhandled exception", e.Exception);
            e.Handled = true;
        };
    }

    /// <summary>Resources and windows need the XAML runtime, which isn't ready in the constructor.</summary>
    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        Resources.MergedDictionaries.Add(new XamlControlsResources());

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

        if (_startPage is not null || firstRun) Show(_startPage ?? "dashboard");
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
