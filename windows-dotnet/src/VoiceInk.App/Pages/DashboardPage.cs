using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using VoiceInk.App.Ui;
using VoiceInk.Core;
using VoiceInk.Core.Config;
using VoiceInk.Platform.Input;

namespace VoiceInk.App.Pages;

/// <summary>Usage statistics, the activity chart, top apps and the latest transcriptions.</summary>
internal static class DashboardPage
{
    private const int ChartDays = 14;
    private const double ChartHeight = 140;

    public static UIElement Build(AppServices services)
    {
        var host = new ContentControl { HorizontalContentAlignment = HorizontalAlignment.Stretch, VerticalContentAlignment = VerticalAlignment.Stretch };
        void Refresh() => host.Content = Render(services);

        Refresh();
        // New dictations show up live while the page is open.
        void OnEntry(HistoryEntry _) => services.RunOnUi(Refresh);
        host.Loaded += (_, _) => services.Dictation.EntryAdded += OnEntry;
        host.Unloaded += (_, _) => services.Dictation.EntryAdded -= OnEntry;
        return host;
    }

    private static UIElement Render(AppServices services)
    {
        var entries = History.Load(AppPaths.HistoryPath);
        var stats = Stats.ComputeNow(entries, ChartDays);
        var cfg = services.Cfg;

        var tiles = new Grid { ColumnSpacing = 8 };
        var values = new (string Glyph, string Value, string Caption)[]
        {
            ("", Stats.FormatCount(stats.Words), "words dictated"),
            ("", Stats.FormatDuration(stats.TimeSavedSecs), "time saved vs. typing"),
            ("", stats.Wpm > 0 ? $"{stats.Wpm:F0}" : "–", "words per minute"),
            ("", Stats.FormatCount(stats.Sessions), "dictations"),
            ("", $"{stats.StreakDays} d", "day streak"),
        };
        for (var i = 0; i < values.Length; i++)
        {
            tiles.ColumnDefinitions.Add(new ColumnDefinition());
            var tile = Fluent.StatTile(values[i].Glyph, values[i].Value, values[i].Caption);
            Grid.SetColumn(tile, i);
            tiles.Children.Add(tile);
        }

        var content = new List<UIElement>();
        if (NeedsKey(cfg))
        {
            content.Add(Fluent.Info(
                "Add an API key to get started",
                $"{cfg.Transcription.Provider.DisplayName()} needs an API key. Open Transcription to add it, or pick Local to dictate offline.",
                InfoBarSeverity.Warning));
        }

        content.Add(Fluent.Card(new StackPanel
        {
            Spacing = 2,
            Children =
            {
                Fluent.BodyStrong("Ready when you are"),
                Fluent.Caption($"Press {cfg.Hotkeys.Record} to start dictating, press it again to stop. {cfg.Hotkeys.Cancel} cancels."
                    + (cfg.Command.Enabled ? $" Select text and press {cfg.Command.Hotkey} for Command Mode." : "")),
            },
        }));
        content.Add(tiles);
        content.Add(Fluent.Section("Last 14 days", Fluent.Card(Chart(stats), new Thickness(16))));
        if (stats.TopApps.Count > 0) content.Add(Fluent.Section("Top apps", Fluent.Card(TopApps(stats), new Thickness(16))));
        content.Add(Fluent.Section("Recent transcriptions", Recent(entries).ToArray()));
        return Fluent.Page("Dashboard", [.. content]);
    }

    private static bool NeedsKey(AppConfig cfg) =>
        cfg.Transcription.Provider.RequiresApiKey() && !Credentials.Has(cfg.Transcription.Provider.KeyName());

    private static UIElement Chart(DashboardStats stats)
    {
        var max = Math.Max(1, stats.DailyWords.Max(d => d.Words));
        var grid = new Grid { ColumnSpacing = 6, Height = ChartHeight + 24 };
        for (var i = 0; i < stats.DailyWords.Count; i++)
        {
            var (date, words) = stats.DailyWords[i];
            grid.ColumnDefinitions.Add(new ColumnDefinition());
            var bar = new Border
            {
                Height = Math.Max(3, ChartHeight * words / max),
                CornerRadius = new CornerRadius(4),
                Background = Fluent.Accent,
                Opacity = words == 0 ? 0.25 : 1,
                VerticalAlignment = VerticalAlignment.Bottom,
            };
            ToolTipService.SetToolTip(bar, $"{date:ddd, d MMM}: {Stats.FormatCount(words)} words");
            var label = Fluent.Caption(date.ToString("dd"));
            label.HorizontalAlignment = HorizontalAlignment.Center;
            var column = new Grid { RowDefinitions = { new RowDefinition { Height = new GridLength(ChartHeight) }, new RowDefinition() } };
            column.Children.Add(bar);
            Grid.SetRow(label, 1);
            column.Children.Add(label);
            Grid.SetColumn(column, i);
            grid.Children.Add(column);
        }

        return grid;
    }

    private static UIElement TopApps(DashboardStats stats)
    {
        var list = new StackPanel { Spacing = 10 };
        var max = stats.TopApps.Max(a => a.Sessions);
        foreach (var (app, sessions) in stats.TopApps)
        {
            var row = new Grid { ColumnSpacing = 12 };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(150) });
            row.ColumnDefinitions.Add(new ColumnDefinition());
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            var name = Fluent.Body(app);
            var bar = new ProgressBar { Minimum = 0, Maximum = max, Value = sessions, VerticalAlignment = VerticalAlignment.Center };
            var count = Fluent.Caption(sessions.ToString());
            Grid.SetColumn(bar, 1);
            Grid.SetColumn(count, 2);
            row.Children.Add(name);
            row.Children.Add(bar);
            row.Children.Add(count);
            list.Children.Add(row);
        }

        return list;
    }

    private static IEnumerable<UIElement> Recent(List<HistoryEntry> entries)
    {
        var recent = entries.AsEnumerable().Reverse().Take(8).ToList();
        if (recent.Count == 0)
        {
            yield return Fluent.Card(Fluent.Caption("Nothing yet. Your dictations will appear here."));
            yield break;
        }

        foreach (var e in recent) yield return EntryCard(e);
    }

    /// <summary>One transcription with a copy button (also used by the history page).</summary>
    public static UIElement EntryCard(HistoryEntry e)
    {
        var meta = string.Join("  ·  ", new[]
        {
            e.Timestamp.LocalDateTime.ToString("g"),
            e.App,
            e.ModeName,
            e.Status == EntryStatus.Completed ? null : e.Status.ToString(),
        }.Where(s => !string.IsNullOrEmpty(s)));

        var text = Fluent.Body(e.FinalText.Length > 0 ? e.FinalText : e.Text);
        text.MaxLines = 4;
        text.TextTrimming = TextTrimming.CharacterEllipsis;
        var copy = new Button
        {
            Content = new FontIcon { Glyph = "", FontSize = 14 },
            VerticalAlignment = VerticalAlignment.Top,
            Padding = new Thickness(8),
        };
        ToolTipService.SetToolTip(copy, "Copy");
        copy.Click += (_, _) => ClipboardApi.SetText(e.FinalText, transient: false);

        var grid = new Grid { ColumnSpacing = 12 };
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.Children.Add(new StackPanel { Spacing = 4, Children = { Fluent.Caption(meta), text } });
        Grid.SetColumn(copy, 1);
        grid.Children.Add(copy);
        return Fluent.Card(grid);
    }
}
