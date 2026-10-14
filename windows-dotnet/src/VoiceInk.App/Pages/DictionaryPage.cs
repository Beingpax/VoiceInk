using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using VoiceInk.App.Ui;
using VoiceInk.Core.Text;

namespace VoiceInk.App.Pages;

internal static class DictionaryPage
{
    public static UIElement Build(AppServices s)
    {
        var cfg = s.Cfg;
        var errors = new StackPanel { Spacing = 4 };

        // Parse errors are shown inline; invalid input is not saved.
        void TryApply<T>(string text, Func<string, List<T>> parse, Action<AppConfigAccess, List<T>> apply)
        {
            errors.Children.Clear();
            try
            {
                var parsed = parse(text);
                s.Update(c => apply(new AppConfigAccess(c), parsed));
            }
            catch (FormatException e)
            {
                errors.Children.Add(Fluent.Info("Not saved", e.Message, InfoBarSeverity.Error));
            }
        }

        return Fluent.Page("Dictionary & Snippets",
            errors,
            Fluent.Section("Custom vocabulary",
                Fluent.Caption("Names and terms the AI and the speech provider should spell correctly. One per line."),
                Fluent.MultiLine(string.Join("\n", cfg.Vocabulary), v => TryApply(v,
                    t => t.Split('\n', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries).ToList(),
                    (a, list) => a.Config.Vocabulary = list), 120, "Kubernetes\nVoiceInk")),
            Fluent.Section("Word replacements",
                Fluent.Caption("One rule per line: spoken -> written. Separate variants with commas. Lines starting with # are comments."),
                Fluent.MultiLine(Replacements.FormatLines(cfg.Replacements), v => TryApply(v, Replacements.ParseLines,
                    (a, list) => a.Config.Replacements = list), 140, "voice ink, voice inc -> VoiceInk")),
            Fluent.Section("Snippets",
                Fluent.Caption("Say the trigger to insert saved text: trigger => text. Use \\n for a line break; {date}, {time} and {datetime} are filled in."),
                Fluent.MultiLine(Snippets.FormatLines(cfg.Snippets), v => TryApply(v, Snippets.ParseLines,
                    (a, list) => a.Config.Snippets = list), 140, "my calendar link => https://cal.com/you")),
            Fluent.Section("Filler words",
                Fluent.Caption("Removed from every transcript. One per line."),
                Fluent.MultiLine(string.Join("\n", cfg.FillerWords), v => TryApply(v,
                    t => t.Split('\n', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries).ToList(),
                    (a, list) => a.Config.FillerWords = list), 100)));
    }

    /// <summary>Lets the generic helper assign to differently typed config lists without reflection.</summary>
    private readonly record struct AppConfigAccess(VoiceInk.Core.Config.AppConfig Config);
}
