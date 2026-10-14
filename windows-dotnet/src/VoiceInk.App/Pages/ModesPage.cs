using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using VoiceInk.App.Ui;
using VoiceInk.Core.Config;

namespace VoiceInk.App.Pages;

/// <summary>Per-app modes: different prompt, language or send key depending on the focused application.</summary>
internal static class ModesPage
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
        var content = new List<UIElement>
        {
            Fluent.Caption("A mode applies when the focused app or window title matches, or when you start a dictation with one of its trigger words (\"email ...\"). Empty fields keep your global settings."),
            Fluent.Button("Add mode", () =>
            {
                s.Update(c => c.Modes.Add(new ModeConfig { Name = "New mode" }));
                rebuild();
            }, accent: true, glyph: ""),
        };
        foreach (var mode in s.Cfg.Modes) content.Add(ModeCard(s, mode, rebuild));
        return Fluent.Page("Modes", [.. content]);
    }

    private static List<string> Split(string text) =>
        text.Split([',', '\n'], StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries).ToList();

    private static readonly (bool? Value, string Label)[] Tri = [(null, "Use global setting"), (true, "On"), (false, "Off")];

    private static UIElement ModeCard(AppServices s, ModeConfig mode, Action rebuild)
    {
        var prompts = new List<(string? Value, string Label)> { (null, "Use global prompt") };
        prompts.AddRange(s.Cfg.Prompts.Select(p => ((string?)p.Id, p.Title)));
        var languages = new List<(string? Value, string Label)> { (null, "Use global language") };
        languages.AddRange(Languages.All.Select(l => ((string?)l.Code, l.Name)));
        var sendKeys = new (SendKey? Value, string Label)[]
        {
            (null, "Use global setting"), (SendKey.None, "Do nothing"), (SendKey.Enter, "Enter"),
            (SendKey.ShiftEnter, "Shift+Enter"), (SendKey.CtrlEnter, "Ctrl+Enter"),
        };

        var body = new StackPanel { Spacing = 4 };
        body.Children.Add(Fluent.Row("Name", null, Fluent.Text(mode.Name, v => { s.Update(_ => mode.Name = v); rebuild(); })));
        body.Children.Add(Fluent.Row("Enabled", null, Fluent.Toggle(mode.Enabled, v => s.Update(_ => mode.Enabled = v))));
        body.Children.Add(Fluent.Row("App names", "Executable names, comma separated: slack.exe, discord.exe",
            Fluent.Text(string.Join(", ", mode.ProcessNames), v => s.Update(_ => mode.ProcessNames = Split(v)), width: 300)));
        body.Children.Add(Fluent.Row("Window title contains", "Comma separated, e.g. Gmail, github.com",
            Fluent.Text(string.Join(", ", mode.WindowTitleContains), v => s.Update(_ => mode.WindowTitleContains = Split(v)), width: 300)));
        body.Children.Add(Fluent.Row("Trigger words", "Say one at the start or end of a dictation to force this mode.",
            Fluent.Text(string.Join(", ", mode.TriggerWords), v => s.Update(_ => mode.TriggerWords = Split(v)), width: 300)));
        body.Children.Add(Fluent.Row("AI Enhancement", null, Fluent.Combo(Tri, mode.EnhancementEnabled, v => s.Update(_ => mode.EnhancementEnabled = v), 200)));
        body.Children.Add(Fluent.Row("Prompt", null, Fluent.Combo(prompts, mode.PromptId, v => s.Update(_ => mode.PromptId = v), 200)));
        body.Children.Add(Fluent.Row("Language", null, Fluent.Combo(languages, mode.Language, v => s.Update(_ => mode.Language = v), 200)));
        body.Children.Add(Fluent.Row("Paragraph formatting", null, Fluent.Combo(Tri, mode.TextFormatting, v => s.Update(_ => mode.TextFormatting = v), 200)));
        body.Children.Add(Fluent.Row("After inserting", "\"Finish & Send\": press a key after the text is inserted.",
            Fluent.Combo(sendKeys, mode.SendKey, v => s.Update(_ => mode.SendKey = v), 200)));
        body.Children.Add(Fluent.Row("Output", "Custom command receives the text on stdin and in %VOICEINK_TRANSCRIPT%.", Fluent.Combo(
            [(OutputMode.Paste, "Insert text"), (OutputMode.CustomCommand, "Run custom command")], mode.Output,
            v => { s.Update(_ => mode.Output = v); }, 200)));
        body.Children.Add(Fluent.Row("Custom command", "Used when Output is a custom command.",
            Fluent.Text(mode.CustomCommand, v => s.Update(_ => mode.CustomCommand = string.IsNullOrWhiteSpace(v) ? null : v), width: 300)));
        body.Children.Add(Fluent.Button("Delete mode", () =>
        {
            s.Update(c => c.Modes.Remove(mode));
            rebuild();
        }));

        return new Expander
        {
            Header = mode.Name.Length == 0 ? "(unnamed)" : mode.Name,
            Content = body,
            HorizontalAlignment = HorizontalAlignment.Stretch,
            HorizontalContentAlignment = HorizontalAlignment.Stretch,
        };
    }
}
