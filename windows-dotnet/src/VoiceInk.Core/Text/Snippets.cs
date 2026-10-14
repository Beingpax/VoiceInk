using System.Globalization;

namespace VoiceInk.Core.Text;

public sealed class Snippet
{
    /// <summary>What you say, e.g. "my calendar link".</summary>
    public string Trigger { get; set; } = "";

    /// <summary>What gets inserted.</summary>
    public string Text { get; set; } = "";
}

public static class Snippets
{
    private const string Punctuation = ".,!?;:\"'„“”‘’…-";

    /// <summary>Lower-cases, collapses whitespace and strips surrounding punctuation.</summary>
    public static string Normalize(string s)
    {
        static bool Strip(char c) => char.IsWhiteSpace(c) || Punctuation.Contains(c, StringComparison.Ordinal);
        var start = 0;
        var end = s.Length;
        while (start < end && Strip(s[start])) start++;
        while (end > start && Strip(s[end - 1])) end--;
        return string.Join(' ', s[start..end].Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries)).ToLowerInvariant();
    }

    /// <summary>Fills in <c>{date}</c>, <c>{time}</c> and <c>{datetime}</c>.</summary>
    public static string Render(string text, DateTime now) => text
        .Replace("{datetime}", now.ToString("yyyy-MM-dd HH:mm", CultureInfo.InvariantCulture), StringComparison.Ordinal)
        .Replace("{date}", now.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture), StringComparison.Ordinal)
        .Replace("{time}", now.ToString("HH:mm", CultureInfo.InvariantCulture), StringComparison.Ordinal);

    /// <summary>The snippet whose trigger is the whole dictation, if any.</summary>
    public static Snippet? ExactMatch(string text, IEnumerable<Snippet> snippets)
    {
        var spoken = Normalize(text);
        if (spoken.Length == 0) return null;
        return snippets.FirstOrDefault(s =>
        {
            var trigger = Normalize(s.Trigger);
            return trigger.Length > 0 && trigger == spoken;
        });
    }

    /// <summary>Expands every trigger phrase found inside <paramref name="text"/> (longest triggers first).</summary>
    public static string ExpandInline(string text, IEnumerable<Snippet> snippets, DateTime now) =>
        snippets
            .Where(s => s.Trigger.Trim().Length > 0)
            .OrderByDescending(s => s.Trigger.Trim().Length)
            .Aggregate(text, (acc, s) => Replacements.ReplacePhrase(acc, s.Trigger.Trim(), Render(s.Text, now)));

    private static readonly string[] Arrows = ["=>", "->", "→"];

    /// <summary>
    /// Parses the settings editor format: one snippet per line, <c>trigger =&gt; text</c>, where <c>\n</c> in the
    /// text stands for a line break. Lines starting with <c>#</c> are comments.
    /// </summary>
    public static List<Snippet> ParseLines(string text)
    {
        var result = new List<Snippet>();
        var lines = text.Split('\n');
        for (var n = 0; n < lines.Length; n++)
        {
            var line = lines[n].Trim();
            if (line.Length == 0 || line.StartsWith('#')) continue;
            var split = Replacements.SplitOnArrow(line, Arrows)
                ?? throw new FormatException($"Snippet line {n + 1} needs \"trigger => text\": {line}");
            var trigger = split.Left.Trim();
            if (trigger.Length == 0)
            {
                throw new FormatException($"Snippet line {n + 1} has no trigger phrase");
            }

            result.Add(new Snippet { Trigger = trigger, Text = split.Right.Trim().Replace("\\n", "\n", StringComparison.Ordinal) });
        }

        return result;
    }

    /// <summary>Inverse of <see cref="ParseLines"/>.</summary>
    public static string FormatLines(IEnumerable<Snippet> snippets) =>
        string.Join("\n", snippets.Select(s => $"{s.Trigger} => {s.Text.Replace("\n", "\\n", StringComparison.Ordinal)}"));
}
