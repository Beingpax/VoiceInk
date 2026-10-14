using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Markup;
using Windows.UI;

namespace VoiceInk.App.Ui;

/// <summary>
/// Small factory for Fluent building blocks. Controls are created in code (no XAML compiler needed); the few
/// theme-aware brushes come from tiny runtime XAML snippets so they follow light/dark mode automatically.
/// </summary>
internal static class Fluent
{
    private static T Load<T>(string xaml) => (T)XamlReader.Load(xaml);

    public static Border Card(UIElement child, Thickness? padding = null)
    {
        var card = Load<Border>("""
            <Border xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' Background="{ThemeResource CardBackgroundFillColorDefaultBrush}"
                    BorderBrush="{ThemeResource CardStrokeColorDefaultBrush}" BorderThickness="1" CornerRadius="8"/>
            """);
        card.Padding = padding ?? new Thickness(16, 12, 16, 12);
        card.Child = child;
        return card;
    }

    public static TextBlock Title(string text) => Styled(text, "TitleTextBlockStyle");
    public static TextBlock Subtitle(string text) => Styled(text, "SubtitleTextBlockStyle");
    public static TextBlock BodyStrong(string text) => Styled(text, "BodyStrongTextBlockStyle");
    public static TextBlock Body(string text) => Styled(text, "BodyTextBlockStyle");

    private static TextBlock Styled(string text, string style) => new()
    {
        Text = text,
        Style = (Style)Application.Current.Resources[style],
        TextWrapping = TextWrapping.Wrap,
    };

    /// <summary>Secondary, smaller text.</summary>
    public static TextBlock Caption(string text)
    {
        var block = Load<TextBlock>("""
            <TextBlock xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' Foreground="{ThemeResource TextFillColorSecondaryBrush}" FontSize="12" TextWrapping="Wrap"/>
            """);
        block.Text = text;
        return block;
    }

    /// <summary>Large number with a caption, used for dashboard stats.</summary>
    public static Border StatTile(string glyph, string value, string caption)
    {
        var icon = new FontIcon { Glyph = glyph, FontSize = 18, Foreground = Accent };
        var number = new TextBlock { Text = value, FontSize = 28, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold };
        var panel = new StackPanel { Spacing = 4, Children = { icon, number, Caption(caption) } };
        return Card(panel, new Thickness(16));
    }

    public static Microsoft.UI.Xaml.Media.Brush Accent =>
        (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["AccentFillColorDefaultBrush"];

    /// <summary>A settings row: title and description on the left, the control on the right.</summary>
    public static Border Row(string title, string? description, UIElement control)
    {
        var text = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Spacing = 2 };
        text.Children.Add(Body(title));
        if (!string.IsNullOrEmpty(description)) text.Children.Add(Caption(description));

        var grid = new Grid { ColumnSpacing = 24 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.Children.Add(text);
        if (control is FrameworkElement fe) fe.VerticalAlignment = VerticalAlignment.Center;
        Grid.SetColumn((FrameworkElement)control, 1);
        grid.Children.Add(control);
        return Card(grid);
    }

    /// <summary>A header followed by a vertical group of cards.</summary>
    public static StackPanel Section(string header, params UIElement[] content)
    {
        var panel = new StackPanel { Spacing = 4 };
        panel.Children.Add(new TextBlock
        {
            Text = header,
            Style = (Style)Application.Current.Resources["BodyStrongTextBlockStyle"],
            Margin = new Thickness(2, 12, 0, 4),
        });
        foreach (var c in content) panel.Children.Add(c);
        return panel;
    }

    /// <summary>Scrollable page with a title and a centered, width-limited column.</summary>
    public static ScrollViewer Page(string title, params UIElement[] content)
    {
        var column = new StackPanel { Spacing = 8, MaxWidth = 900, HorizontalAlignment = HorizontalAlignment.Stretch };
        column.Children.Add(new TextBlock
        {
            Text = title,
            Style = (Style)Application.Current.Resources["TitleTextBlockStyle"],
            Margin = new Thickness(0, 0, 0, 4),
        });
        foreach (var c in content) column.Children.Add(c);
        return new ScrollViewer
        {
            Content = new Grid { Padding = new Thickness(36, 8, 36, 36), Children = { column } },
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
        };
    }

    // -- bound controls --------------------------------------------------------------------

    public static ToggleSwitch Toggle(bool value, Action<bool> set)
    {
        var toggle = new ToggleSwitch { IsOn = value, OnContent = "", OffContent = "", MinWidth = 0 };
        toggle.Toggled += (_, _) => set(toggle.IsOn);
        return toggle;
    }

    public static ComboBox Combo<T>(IReadOnlyList<(T Value, string Label)> items, T selected, Action<T> set, double width = 240)
    {
        var combo = new ComboBox { Width = width };
        foreach (var (_, label) in items) combo.Items.Add(label);
        combo.SelectedIndex = Math.Max(0, items.ToList().FindIndex(i => EqualityComparer<T>.Default.Equals(i.Value, selected)));
        combo.SelectionChanged += (_, _) =>
        {
            if (combo.SelectedIndex >= 0) set(items[combo.SelectedIndex].Value);
        };
        return combo;
    }

    /// <summary>Single-line text applied when focus leaves or Enter is pressed.</summary>
    public static TextBox Text(string? value, Action<string> set, string? placeholder = null, double width = 260)
    {
        var box = new TextBox { Text = value ?? "", PlaceholderText = placeholder ?? "", Width = width };
        var last = box.Text;
        void Commit()
        {
            if (box.Text == last) return;
            last = box.Text;
            set(box.Text);
        }

        box.LostFocus += (_, _) => Commit();
        box.KeyDown += (_, e) =>
        {
            if (e.Key == Windows.System.VirtualKey.Enter) Commit();
        };
        return box;
    }

    public static TextBox MultiLine(string value, Action<string> set, double height = 140, string? placeholder = null)
    {
        var box = new TextBox
        {
            Text = value,
            PlaceholderText = placeholder ?? "",
            AcceptsReturn = true,
            TextWrapping = TextWrapping.Wrap,
            MinHeight = height,
            FontFamily = new Microsoft.UI.Xaml.Media.FontFamily("Cascadia Mono, Consolas"),
            HorizontalAlignment = HorizontalAlignment.Stretch,
        };
        var last = value;
        box.LostFocus += (_, _) =>
        {
            if (box.Text == last) return;
            last = box.Text;
            set(box.Text);
        };
        return box;
    }

    public static NumberBox Number(double value, double min, double max, Action<double> set, double step = 1)
    {
        var box = new NumberBox
        {
            Value = value,
            Minimum = min,
            Maximum = max,
            SmallChange = step,
            SpinButtonPlacementMode = NumberBoxSpinButtonPlacementMode.Inline,
            Width = 140,
        };
        box.ValueChanged += (_, e) =>
        {
            if (!double.IsNaN(e.NewValue)) set(e.NewValue);
        };
        return box;
    }

    public static Button Button(string text, Action click, bool accent = false, string? glyph = null)
    {
        var content = glyph is null
            ? (object)text
            : new StackPanel
            {
                Orientation = Orientation.Horizontal,
                Spacing = 8,
                Children = { new FontIcon { Glyph = glyph, FontSize = 14 }, new TextBlock { Text = text } },
            };
        var button = new Button { Content = content };
        if (accent) button.Style = (Style)Application.Current.Resources["AccentButtonStyle"];
        button.Click += (_, _) => click();
        return button;
    }

    public static InfoBar Info(string title, string message, InfoBarSeverity severity = InfoBarSeverity.Informational) => new()
    {
        Title = title,
        Message = message,
        Severity = severity,
        IsOpen = true,
        IsClosable = false,
    };

    public static StackPanel Horizontal(double spacing = 8, params UIElement[] children)
    {
        var panel = new StackPanel { Orientation = Orientation.Horizontal, Spacing = spacing };
        foreach (var c in children) panel.Children.Add(c);
        return panel;
    }

    public static Color Hex(string hex) => Color.FromArgb(
        255, Convert.ToByte(hex[1..3], 16), Convert.ToByte(hex[3..5], 16), Convert.ToByte(hex[5..7], 16));
}
