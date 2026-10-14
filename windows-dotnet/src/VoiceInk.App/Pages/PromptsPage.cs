using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using VoiceInk.App.Ui;
using VoiceInk.Core;

namespace VoiceInk.App.Pages;

/// <summary>Prompt editor: pick a prompt on the left, edit it on the right.</summary>
internal static class PromptsPage
{
    public static UIElement Build(AppServices s) => Build(s, s.Cfg.Prompts.FirstOrDefault()?.Id);

    private static UIElement Build(AppServices s, string? selectedId)
    {
        var host = new ContentControl { HorizontalContentAlignment = HorizontalAlignment.Stretch, VerticalContentAlignment = VerticalAlignment.Stretch };
        void Render(string? id) => host.Content = Create(s, id, Render);
        Render(selectedId);
        return host;
    }

    private static UIElement Create(AppServices s, string? selectedId, Action<string?> rebuild)
    {
        var prompts = s.Cfg.Prompts;
        var selected = prompts.FirstOrDefault(p => p.Id == selectedId) ?? prompts.FirstOrDefault();

        var picker = Fluent.Combo([.. prompts.Select(p => (p.Id, p.Title))], selected?.Id ?? "", id => rebuild(id), 260);
        var add = Fluent.Button("New prompt", () =>
        {
            var prompt = new CustomPrompt { Id = Guid.NewGuid().ToString(), Title = "New prompt", PromptText = "<TASK>\nClean <TRANSCRIPT> into ...\n</TASK>" };
            s.Update(c => c.Prompts.Add(prompt));
            rebuild(prompt.Id);
        }, glyph: "");
        var toolbar = Fluent.Horizontal(8, picker, add);

        var content = new List<UIElement> { Fluent.Card(toolbar) };
        if (selected is not null)
        {
            var isActive = s.Cfg.Enhancement.PromptId == selected.Id;
            var title = Fluent.Text(selected.Title, v => { s.Update(_ => selected.Title = v); rebuild(selected.Id); }, width: 320);
            var body = Fluent.MultiLine(selected.PromptText, v => s.Update(_ => selected.PromptText = v), 320);
            var actions = Fluent.Horizontal(8,
                Fluent.Button(isActive ? "Active prompt" : "Use for AI Enhancement", () =>
                {
                    s.Update(c => c.Enhancement.PromptId = selected.Id);
                    rebuild(selected.Id);
                }, accent: !isActive),
                Fluent.Button("Delete", () =>
                {
                    if (prompts.Count <= 1) return;
                    s.Update(c =>
                    {
                        c.Prompts.RemoveAll(p => p.Id == selected.Id);
                        if (c.Enhancement.PromptId == selected.Id) c.Enhancement.PromptId = c.Prompts[0].Id;
                    });
                    rebuild(null);
                }),
                Fluent.Button("Restore built-in prompts", () =>
                {
                    s.Update(c =>
                    {
                        foreach (var seed in PromptTemplates.Seed())
                        {
                            var existing = c.Prompts.FirstOrDefault(p => p.Id == seed.Id);
                            if (existing is null) c.Prompts.Add(seed);
                            else
                            {
                                existing.Title = seed.Title;
                                existing.PromptText = seed.PromptText;
                                existing.UseSystemInstructions = seed.UseSystemInstructions;
                            }
                        }
                    });
                    rebuild(selected.Id);
                }));

            content.Add(Fluent.Row("Name", null, title));
            content.Add(Fluent.Row("Wrap with VoiceInk rules", "Adds the standard transcript-cleaning rules and examples around your instructions.",
                Fluent.Toggle(selected.UseSystemInstructions, v => s.Update(_ => selected.UseSystemInstructions = v))));
            content.Add(Fluent.Section("Instructions", body));
            content.Add(Fluent.Caption("Use <TRANSCRIPT> to refer to the dictated text. Applied when you leave the text box."));
            content.Add(actions);
        }

        return Fluent.Page("Prompts", [.. content]);
    }
}
