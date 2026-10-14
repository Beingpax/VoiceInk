using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using VoiceInk.App.Ui;
using VoiceInk.Core;
using VoiceInk.Core.Config;

namespace VoiceInk.App.Pages;

internal static class HistoryPage
{
    private const int PageSize = 100;

    public static UIElement Build(AppServices s)
    {
        var entries = History.Load(AppPaths.HistoryPath).AsEnumerable().Reverse().ToList();
        var list = new StackPanel { Spacing = 6 };
        var search = new TextBox { PlaceholderText = "Search transcriptions", Width = 320 };

        void Fill()
        {
            list.Children.Clear();
            var query = search.Text.Trim();
            var shown = entries
                .Where(e => query.Length == 0 || e.FinalText.Contains(query, StringComparison.OrdinalIgnoreCase)
                    || (e.App?.Contains(query, StringComparison.OrdinalIgnoreCase) ?? false))
                .Take(PageSize)
                .ToList();
            if (shown.Count == 0) list.Children.Add(Fluent.Card(Fluent.Caption("No transcriptions found.")));
            foreach (var e in shown) list.Children.Add(DashboardPage.EntryCard(e));
        }

        search.TextChanged += (_, _) => Fill();
        Fill();

        var export = Fluent.Button("Export CSV", () => _ = ExportAsync(entries), glyph: "");
        var clear = Fluent.Button("Clear history", () =>
        {
            History.Clear(AppPaths.HistoryPath);
            entries.Clear();
            Fill();
        }, glyph: "");

        return Fluent.Page("History", Fluent.Horizontal(8, search, export, clear), list,
            Fluent.Caption($"Showing the latest {PageSize} matches. The full history is in {AppPaths.HistoryPath}."));
    }

    private static async Task ExportAsync(List<HistoryEntry> entries)
    {
        var picker = new Windows.Storage.Pickers.FileSavePicker { SuggestedFileName = "voiceink-history" };
        picker.FileTypeChoices.Add("CSV", [".csv"]);
        // Unpackaged apps must tell the picker which window owns it.
        var hwnd = System.Diagnostics.Process.GetCurrentProcess().MainWindowHandle;
        WinRT.Interop.InitializeWithWindow.Initialize(picker, hwnd);
        var file = await picker.PickSaveFileAsync();
        if (file is null) return;
        await using var stream = File.Create(file.Path);
        await using var writer = new StreamWriter(stream, new System.Text.UTF8Encoding(true));
        History.ExportCsv(entries.AsEnumerable().Reverse(), writer);
    }
}
