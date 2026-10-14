using Microsoft.UI;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using VoiceInk.App.Ui;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using VoiceInk.Core.Config;
using VoiceInk.Core.Dictation;
using VoiceInk.Platform.Shell;
using WinRT.Interop;

namespace VoiceInk.App.Views;

/// <summary>
/// The recorder pill: a small acrylic, always-on-top window that never takes focus. It shows a live level meter
/// while recording, a spinner while processing, and a short message on errors. Click it to stop.
/// </summary>
internal sealed class OverlayWindow : Window
{
    private const int BarCount = 14;
    private const int Width = 232, Height = 48;

    private readonly Func<OverlayPosition> _position;
    private readonly Action _onClick;
    private readonly Rectangle[] _bars = new Rectangle[BarCount];
    private readonly float[] _levels = new float[BarCount];
    private readonly TextBlock _label = new() { VerticalAlignment = VerticalAlignment.Center, FontSize = 13 };
    private readonly TextBlock _time = new() { VerticalAlignment = VerticalAlignment.Center, FontSize = 13, Opacity = 0.7 };
    private readonly Ellipse _dot = new() { Width = 10, Height = 10, Fill = new SolidColorBrush(Colors.IndianRed) };
    private readonly ProgressRing _ring = new() { Width = 18, Height = 18, IsActive = true, Visibility = Visibility.Collapsed };
    private readonly StackPanel _meter = new() { Orientation = Orientation.Horizontal, Spacing = 3, VerticalAlignment = VerticalAlignment.Center };
    private readonly DispatcherQueueTimer _timer;
    private DictationStatus _status = new(Phase.Idle);
    private readonly nint _hwnd;

    public OverlayWindow(Func<OverlayPosition> position, Action onClick)
    {
        _position = position;
        _onClick = onClick;
        _hwnd = WindowNative.GetWindowHandle(this);

        for (var i = 0; i < BarCount; i++)
        {
            _bars[i] = new Rectangle { Width = 3, Height = 4, RadiusX = 1.5, RadiusY = 1.5, VerticalAlignment = VerticalAlignment.Center, Fill = Fluent.Accent };
            _meter.Children.Add(_bars[i]);
        }

        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10, VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Center };
        row.Children.Add(_dot);
        row.Children.Add(_ring);
        row.Children.Add(_meter);
        row.Children.Add(_label);
        row.Children.Add(_time);
        var root = new Grid { Background = new SolidColorBrush(Colors.Transparent), Children = { row } };
        root.Tapped += (_, _) => _onClick();
        Content = root;
        SystemBackdrop = new DesktopAcrylicBackdrop();

        var presenter = (OverlappedPresenter)AppWindow.Presenter;
        presenter.IsAlwaysOnTop = true;
        presenter.IsResizable = false;
        presenter.IsMaximizable = false;
        presenter.IsMinimizable = false;
        presenter.SetBorderAndTitleBar(false, false);
        AppWindow.IsShownInSwitchers = false;
        WindowInterop.MakeNonActivatingOverlay(_hwnd);

        _timer = DispatcherQueue.GetForCurrentThread().CreateTimer();
        _timer.Interval = TimeSpan.FromMilliseconds(50);
        _timer.Tick += (_, _) => Tick();
    }

    public void Apply(DictationStatus status)
    {
        _status = status;
        if (_position() == OverlayPosition.Hidden || (status.Phase == Phase.Idle && status.Message is null))
        {
            _timer.Stop();
            AppWindow.Hide();
            return;
        }

        var recording = status.Phase == Phase.Recording;
        _meter.Visibility = _time.Visibility = _dot.Visibility = recording ? Visibility.Visible : Visibility.Collapsed;
        _ring.Visibility = status.Phase is Phase.Transcribing or Phase.Enhancing ? Visibility.Visible : Visibility.Collapsed;
        _label.Text = status.Phase switch
        {
            Phase.Recording => status.ModeLabel ?? "Listening",
            Phase.Transcribing => "Transcribing…",
            Phase.Enhancing => "Enhancing…",
            _ => status.Message ?? "",
        };
        Array.Clear(_levels);
        Place();
        AppWindow.Show(activateWindow: false);
        if (recording) _timer.Start();
        else _timer.Stop();

        if (status.Message is not null) _ = HideAfterAsync(status);
    }

    private async Task HideAfterAsync(DictationStatus shown)
    {
        await Task.Delay(TimeSpan.FromSeconds(3));
        if (ReferenceEquals(_status, shown)) AppWindow.Hide();
    }

    private void Tick()
    {
        var level = _status.Level?.Invoke() ?? 0f;
        Array.Copy(_levels, 1, _levels, 0, BarCount - 1);
        _levels[^1] = level;
        for (var i = 0; i < BarCount; i++) _bars[i].Height = 4 + (_levels[i] * 26);
        if (_status.Elapsed?.Invoke() is { } elapsed) _time.Text = $"{(int)elapsed.TotalMinutes}:{elapsed.Seconds:00}";
    }

    private void Place()
    {
        var scale = WindowInterop.GetScale(_hwnd);
        var area = DisplayArea.Primary.WorkArea;
        var width = (int)(Width * scale);
        var height = (int)(Height * scale);
        var x = area.X + ((area.Width - width) / 2);
        var margin = (int)(56 * scale);
        var y = _position() == OverlayPosition.TopCenter ? area.Y + margin / 2 : area.Y + area.Height - height - margin;
        AppWindow.MoveAndResize(new Windows.Graphics.RectInt32(x, y, width, height));
    }
}
