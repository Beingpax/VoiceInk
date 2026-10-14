using Microsoft.UI;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using VoiceInk.App.Pages;
using VoiceInk.Core.Config;
using WinRT.Interop;

namespace VoiceInk.App.Views;

/// <summary>Dashboard &amp; Settings: Mica window with a left navigation pane. Closing hides it; the app lives in the tray.</summary>
internal sealed class MainWindow : Window
{
    private sealed record PageInfo(string Key, string Title, string Glyph, Func<AppServices, UIElement> Build);

    private static readonly PageInfo[] Pages =
    [
        new("dashboard", "Dashboard", "", DashboardPage.Build),
        new("general", "General", "", GeneralPage.Build),
        new("transcription", "Transcription", "", TranscriptionPage.Build),
        new("models", "Local models", "", ModelsPage.Build),
        new("enhancement", "AI Enhancement", "", EnhancementPage.Build),
        new("prompts", "Prompts", "", PromptsPage.Build),
        new("dictionary", "Dictionary & Snippets", "", DictionaryPage.Build),
        new("modes", "Modes", "", ModesPage.Build),
        new("output", "Output & Audio", "", OutputPage.Build),
        new("history", "History", "", HistoryPage.Build),
    ];

    private readonly AppServices _services;
    private readonly NavigationView _nav;
    private readonly ContentControl _host = new() { HorizontalContentAlignment = HorizontalAlignment.Stretch, VerticalContentAlignment = VerticalAlignment.Stretch };
    private bool _forceClose;

    public MainWindow(AppServices services)
    {
        _services = services;
        Title = "VoiceInk";
        SystemBackdrop = new MicaBackdrop();
        ExtendsContentIntoTitleBar = true;
        AppWindow.SetIcon(Path.Combine(AppContext.BaseDirectory, "Assets", "voiceink.ico"));
        AppWindow.Resize(new Windows.Graphics.SizeInt32(1180, 800));
        AppWindow.Closing += (_, e) =>
        {
            if (_forceClose) return;
            e.Cancel = true;
            AppWindow.Hide();
        };

        _nav = new NavigationView
        {
            PaneDisplayMode = NavigationViewPaneDisplayMode.Left,
            IsBackButtonVisible = NavigationViewBackButtonVisible.Collapsed,
            IsSettingsVisible = false,
            OpenPaneLength = 250,
            IsTitleBarAutoPaddingEnabled = false,
            Content = _host,
        };
        foreach (var p in Pages)
        {
            _nav.MenuItems.Add(new NavigationViewItem { Content = p.Title, Tag = p.Key, Icon = new FontIcon { Glyph = p.Glyph } });
        }

        _nav.SelectionChanged += (_, e) =>
        {
            if (e.SelectedItem is NavigationViewItem { Tag: string key }) Show(key);
        };

        var titleBar = new Grid { Height = 40, Padding = new Thickness(16, 0, 0, 0) };
        titleBar.Children.Add(new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = 10,
            VerticalAlignment = VerticalAlignment.Center,
            Children =
            {
                new Image { Width = 16, Height = 16, Source = new Microsoft.UI.Xaml.Media.Imaging.BitmapImage(new Uri(Path.Combine(AppContext.BaseDirectory, "Assets", "voiceink.ico"))) },
                new TextBlock { Text = "VoiceInk", FontSize = 12, VerticalAlignment = VerticalAlignment.Center },
            },
        });

        var root = new Grid();
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        root.Children.Add(titleBar);
        Grid.SetRow(_nav, 1);
        root.Children.Add(_nav);
        Content = root;
        SetTitleBar(titleBar);
        ApplyTheme();
        services.Config.Changed += () => services.RunOnUi(ApplyTheme);
    }

    private void ApplyTheme()
    {
        if (Content is FrameworkElement root)
        {
            root.RequestedTheme = _services.Cfg.Theme switch
            {
                AppTheme.Light => ElementTheme.Light,
                AppTheme.Dark => ElementTheme.Dark,
                _ => ElementTheme.Default,
            };
        }
    }

    public void Navigate(string key)
    {
        var item = _nav.MenuItems.OfType<NavigationViewItem>().FirstOrDefault(i => (string)i.Tag == key)
            ?? (NavigationViewItem)_nav.MenuItems[0];
        if (ReferenceEquals(_nav.SelectedItem, item)) Show((string)item.Tag); // refresh when re-opened
        else _nav.SelectedItem = item;
    }

    private void Show(string key)
    {
        var page = Pages.FirstOrDefault(p => p.Key == key) ?? Pages[0];
        _host.Content = page.Build(_services);
    }

    /// <summary>Brings the window to the front (it stays hidden in the tray until asked for).</summary>
    public void Present()
    {
        AppWindow.Show();
        Activate();
        SetForegroundWindow(WindowNative.GetWindowHandle(this));
    }

    public void ForceClose()
    {
        _forceClose = true;
        Close();
    }

    [System.Runtime.InteropServices.DllImport("user32.dll")]
    [return: System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.Bool)]
    private static extern bool SetForegroundWindow(nint hwnd);
}
