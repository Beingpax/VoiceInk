using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using VoiceInk.App.Ui;
using VoiceInk.Core.Config;

namespace VoiceInk.App.Pages;

internal static class TranscriptionPage
{
    public static UIElement Build(AppServices s)
    {
        var host = new ContentControl { HorizontalContentAlignment = HorizontalAlignment.Stretch, VerticalContentAlignment = VerticalAlignment.Stretch };
        void Render() => host.Content = Create(s, Render);
        Render();
        return host;
    }

    private static UIElement Create(AppServices s, Action rebuild)
    {
        var t = s.Cfg.Transcription;
        var provider = t.Provider;

        var rows = new List<UIElement>
        {
            Fluent.Row("Provider", null, Fluent.Combo(
                [.. TranscriptionProviders.All.Select(p => (p, p.DisplayName()))], provider,
                v =>
                {
                    s.Update(c => { c.Transcription.Provider = v; c.Transcription.Model = null; });
                    rebuild();
                })),
        };

        if (provider.RequiresApiKey()) rows.Add(ApiKeyRow.Create(provider.KeyName(), provider.DisplayName()));
        if (provider == TranscriptionProvider.Custom)
        {
            rows.Add(Fluent.Row("Endpoint", "Full URL of an OpenAI-compatible /audio/transcriptions endpoint.",
                Fluent.Text(t.CustomEndpoint, v => s.Update(c => c.Transcription.CustomEndpoint = v), width: 360)));
            rows.Add(ApiKeyRow.Create(provider.KeyName(), "Endpoint (optional)"));
        }

        var models = provider.Models();
        rows.Add(models.Count > 0
            ? Fluent.Row("Model", $"Default: {provider.DefaultModel()}",
                Fluent.Combo([.. models.Select(m => (m, m))], t.ModelName, v => s.Update(c => c.Transcription.Model = v), 260))
            : Fluent.Row("Model", provider == TranscriptionProvider.Local ? "File name inside the models folder. Manage models under Local models." : "Model name sent to the endpoint.",
                Fluent.Text(t.Model, v => s.Update(c => c.Transcription.Model = string.IsNullOrWhiteSpace(v) ? null : v.Trim()), provider.DefaultModel())));

        rows.Add(Fluent.Row("Language", "Auto-detect works for most providers; a fixed language is faster and more accurate.", Fluent.Combo(
            [.. Languages.All.Select(l => (l.Code, l.Name))], string.IsNullOrWhiteSpace(t.Language) ? "auto" : t.Language,
            v => s.Update(c => c.Transcription.Language = v), 200)));
        rows.Add(Fluent.Row("Timeout", "Seconds to wait for a transcription.", Fluent.Number(t.TimeoutSecs, 10, 600, v => s.Update(c => c.Transcription.TimeoutSecs = (ulong)v), 10)));

        return Fluent.Page("Transcription",
            Fluent.Section("Speech recognition", [.. rows]),
            Fluent.Section("Cleanup",
                Fluent.Row("Filter output", "Removes [MUSIC], (laughs), tag blocks and filler words.", Fluent.Toggle(t.FilterOutput, v => s.Update(c => c.Transcription.FilterOutput = v))),
                Fluent.Row("Paragraph formatting", "Groups sentences into readable paragraphs.", Fluent.Toggle(t.TextFormatting, v => s.Update(c => c.Transcription.TextFormatting = v)))));
    }
}
