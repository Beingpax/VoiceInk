using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace VoiceInk.Core.Text;

public sealed class WordReplacement
{
    /// <summary>One or more comma-separated source spellings.</summary>
    public string Original { get; set; } = "";

    public string Replacement { get; set; } = "";
}

public static class Replacements
{
    public static List<string> ParseVariants(string text)
    {
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        return text.Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries)
            .Where(v => seen.Add(v))
            .ToList();
    }

    private static bool UsesWordBoundaries(string text) => !text.EnumerateRunes().Any(Words.IsUnspacedScript);

    /// <summary>Applies the dictionary: whole-word, case-insensitive, longest variant first; CJK uses substrings.</summary>
    public static string Apply(string text, IEnumerable<WordReplacement> rules)
    {
        var variants = rules
            .SelectMany(r => ParseVariants(r.Original).Select(v => (Original: v, r.Replacement)))
            .OrderByDescending(v => v.Original.EnumerateRunes().Count())
            .ThenBy(v => v.Original.ToLowerInvariant(), StringComparer.Ordinal)
            .ToList();

        var output = text;
        foreach (var (original, replacement) in variants)
        {
            output = ReplaceCore(output, original, replacement);
        }

        return output;
    }

    /// <summary>
    /// Replaces whole-phrase occurrences of <paramref name="phrase"/> (case-insensitive) with
    /// <paramref name="replacement"/> literally, using the same boundary rules as dictionary replacements.
    /// </summary>
    public static string ReplacePhrase(string text, string phrase, string replacement)
    {
        phrase = phrase.Trim();
        return phrase.Length == 0 ? text : ReplaceCore(text, phrase, replacement);
    }

    private static string ReplaceCore(string text, string phrase, string replacement)
    {
        var re = new Regex(Regex.Escape(phrase), RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
        return UsesWordBoundaries(phrase)
            ? ReplaceBounded(text, re, replacement)
            : re.Replace(text, _ => replacement);
    }

    /// <summary>Word characters for boundary checks: letters, marks and numbers, except unspaced scripts.</summary>
    private static bool IsWordChar(Rune r) =>
        ((Rune.IsLetter(r) || Rune.IsNumber(r)) && !Words.IsUnspacedScript(r)) || IsCombiningMark(r);

    private static bool IsCombiningMark(Rune r) => r.Value is
        (>= 0x0300 and <= 0x036F) or (>= 0x1AB0 and <= 0x1AFF) or (>= 0x1DC0 and <= 0x1DFF)
        or (>= 0x20D0 and <= 0x20FF) or (>= 0xFE20 and <= 0xFE2F);

    private static bool WordCharBefore(string text, int index)
    {
        if (index <= 0) return false;
        var start = char.IsLowSurrogate(text[index - 1]) && index >= 2 ? index - 2 : index - 1;
        return Rune.TryGetRuneAt(text, start, out var r) && IsWordChar(r);
    }

    private static bool WordCharAt(string text, int index) =>
        index < text.Length && Rune.TryGetRuneAt(text, index, out var r) && IsWordChar(r);

    /// <summary>Equivalent of <c>(?&lt;!\w)pattern(?!\w)</c> with the custom word-character definition.</summary>
    private static string ReplaceBounded(string text, Regex re, string replacement)
    {
        var sb = new StringBuilder(text.Length);
        var last = 0;
        var search = 0;
        while (search <= text.Length)
        {
            var m = re.Match(text, search);
            if (!m.Success) break;
            var beforeOk = !WordCharBefore(text, m.Index);
            var afterOk = !WordCharAt(text, m.Index + m.Length);
            if (beforeOk && afterOk && m.Length > 0)
            {
                sb.Append(text, last, m.Index - last).Append(replacement);
                last = m.Index + m.Length;
                search = last;
            }
            else
            {
                // Retry one character later so overlapping candidates are considered.
                search = m.Index + 1;
            }
        }

        sb.Append(text, last, text.Length - last);
        return sb.ToString();
    }

    private static readonly string[] Arrows = ["->", "=>", "→"];

    /// <summary>Parses <c>spoken -&gt; written</c> lines (also accepts <c>=&gt;</c> and <c>→</c>).</summary>
    public static List<WordReplacement> ParseLines(string text)
    {
        var result = new List<WordReplacement>();
        var lines = text.Split('\n');
        for (var n = 0; n < lines.Length; n++)
        {
            var line = lines[n].Trim();
            if (line.Length == 0 || line.StartsWith('#')) continue;
            var split = SplitOnArrow(line);
            if (split is null)
            {
                throw new FormatException(
                    string.Create(CultureInfo.InvariantCulture, $"Replacement line {n + 1} needs \"spoken -> written\": {line}"));
            }

            var (original, replacement) = (split.Value.Left.Trim(), split.Value.Right.Trim());
            if (original.Length == 0)
            {
                throw new FormatException($"Replacement line {n + 1} has nothing before ->");
            }

            result.Add(new WordReplacement { Original = original, Replacement = replacement });
        }

        return result;
    }

    internal static (string Left, string Right)? SplitOnArrow(string line, string[]? arrows = null)
    {
        foreach (var sep in arrows ?? Arrows)
        {
            var i = line.IndexOf(sep, StringComparison.Ordinal);
            if (i >= 0) return (line[..i], line[(i + sep.Length)..]);
        }

        return null;
    }

    public static string FormatLines(IEnumerable<WordReplacement> rules) =>
        string.Join("\n", rules.Select(r => $"{r.Original} -> {r.Replacement}"));
}
