using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using VoiceInk.App.Ui;
using VoiceInk.Core.Config;

namespace VoiceInk.App.Pages;

internal static class EnhancementPage
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
        var e = s.Cfg.Enhancement;
        var provider = e.Provider;

        var providerRows = new List<UIElement>
        {
            Fluent.Row("Provider", null, Fluent.Combo(
                [.. EnhancementProviders.All.Select(p => (p, p.DisplayName()))], provider,
                v =>
                {
                    s.Update(c => { c.Enhancement.Provider = v; c.Enhancement.Model = null; });
                    rebuild();
                })),
        };
        if (provider.RequiresApiKey()) providerRows.Add(ApiKeyRow.Create(provider.KeyName(), provider.DisplayName()));
        if (provider == EnhancementProvider.Ollama)
        {
            providerRows.Add(Fluent.Row("Ollama URL", null, Fluent.Text(e.OllamaBaseUrl, v => s.Update(c => c.Enhancement.OllamaBaseUrl = v), width: 300)));
        }

        if (provider == EnhancementProvider.Custom)
        {
            providerRows.Add(Fluent.Row("Endpoint", "OpenAI-compatible /chat/completions URL (LM Studio, vLLM, ...).",
                Fluent.Text(e.CustomEndpoint, v => s.Update(c => c.Enhancement.CustomEndpoint = v), width: 360)));
            providerRows.Add(ApiKeyRow.Create(provider.KeyName(), "Endpoint (optional)"));
        }

        var models = provider.Models();
        providerRows.Add(models.Count > 0
            ? Fluent.Row("Model", $"Default: {provider.DefaultModel()}",
                Fluent.Combo([.. models.Select(m => (m, m))], e.ModelName, v => s.Update(c => c.Enhancement.Model = v), 260))
            : Fluent.Row("Model", "Model name as the provider expects it.",
                Fluent.Text(e.Model, v => s.Update(c => c.Enhancement.Model = string.IsNullOrWhiteSpace(v) ? null : v.Trim()), provider.DefaultModel())));

        var prompts = s.Cfg.Prompts;
        return Fluent.Page("AI Enhancement",
            Fluent.Section("Enhancement",
                Fluent.Row("Enable AI Enhancement", "Cleans up every dictation with a language model before it is inserted.",
                    Fluent.Toggle(e.Enabled, v => s.Update(c => c.Enhancement.Enabled = v))),
                Fluent.Row("Prompt", "Edit or add prompts under Prompts.", Fluent.Combo(
                    [.. prompts.Select(p => (p.Id, p.Title))], e.PromptId, v => s.Update(c => c.Enhancement.PromptId = v), 220))),
            Fluent.Section("Provider", [.. providerRows]),
            Fluent.Section("Context sent to the model",
                Fluent.Row("Active window", "Application and window title, to get names and jargon right.", Fluent.Toggle(e.UseWindowContext, v => s.Update(c => c.Enhancement.UseWindowContext = v))),
                Fluent.Row("Clipboard text", null, Fluent.Toggle(e.UseClipboardContext, v => s.Update(c => c.Enhancement.UseClipboardContext = v))),
                Fluent.Row("Selected text", "Copies the selection (Ctrl+C) when recording starts.", Fluent.Toggle(e.UseSelectedTextContext, v => s.Update(c => c.Enhancement.UseSelectedTextContext = v)))),
            Fluent.Section("Reliability",
                Fluent.Row("Skip short transcripts", "Insert very short dictations as they are.", Fluent.Toggle(e.SkipShortTranscripts, v => s.Update(c => c.Enhancement.SkipShortTranscripts = v))),
                Fluent.Row("Short means up to (words)", null, Fluent.Number(e.ShortTranscriptWordThreshold, 1, 50, v => s.Update(c => c.Enhancement.ShortTranscriptWordThreshold = (int)v))),
                Fluent.Row("Attempts", "Retries with backoff on rate limits and server errors.", Fluent.Number(e.MaxAttempts, 1, 6, v => s.Update(c => c.Enhancement.MaxAttempts = (uint)v))),
                Fluent.Row("Timeout", "Seconds per request.", Fluent.Number(e.TimeoutSecs, 5, 300, v => s.Update(c => c.Enhancement.TimeoutSecs = (ulong)v), 5))));
    }
}
