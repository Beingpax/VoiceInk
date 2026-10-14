using VoiceInk.Core.Config;

namespace VoiceInk.Core;

/// <summary>Information about the window that was focused when recording started.</summary>
public sealed record ForegroundInfo(string ProcessName = "", string WindowTitle = "");

/// <summary>Effective settings for one dictation after applying a mode.</summary>
public sealed record ResolvedSettings(
    string? ModeName,
    string? Language,
    bool TextFormatting,
    bool EnhancementEnabled,
    EnhancementProvider Provider,
    string Model,
    string PromptId,
    bool UseClipboardContext,
    bool UseSelectedTextContext,
    bool UseWindowContext,
    OutputMode Output,
    string? CustomCommand,
    SendKey SendKey);

/// <summary>Result of detecting a trigger word in a transcript.</summary>
public sealed record TriggerDetection(int ModeIndex, string ProcessedText);

/// <summary>
/// Modes: per-application settings overrides and spoken trigger words
/// (port of <c>ModeConfig</c> matching and <c>ModeTriggerWordDetectionService</c>).
/// </summary>
public static class Modes
{
    /// <summary>Picks the first enabled mode whose process name or title filter matches.</summary>
    public static ModeConfig? Match(IEnumerable<ModeConfig> modes, ForegroundInfo fg)
    {
        var process = fg.ProcessName.ToLowerInvariant();
        var title = fg.WindowTitle.ToLowerInvariant();
        return modes.Where(m => m.Enabled).FirstOrDefault(m =>
        {
            var processHit = m.ProcessNames.Any(p =>
            {
                var name = p.Trim().ToLowerInvariant();
                return name.Length > 0 && (process == name || StripExe(process) == StripExe(name));
            });
            var titleHit = m.WindowTitleContains
                .Select(t => t.Trim().ToLowerInvariant())
                .Any(t => t.Length > 0 && title.Contains(t, StringComparison.Ordinal));
            return processHit || titleHit;
        });
    }

    private static string StripExe(string s) => s.EndsWith(".exe", StringComparison.Ordinal) ? s[..^4] : s;

    public static ResolvedSettings Resolve(AppConfig config, ModeConfig? mode)
    {
        var e = config.Enhancement;
        var r = new ResolvedSettings(
            ModeName: null,
            Language: config.Transcription.LanguageCode,
            TextFormatting: config.Transcription.TextFormatting,
            EnhancementEnabled: e.Enabled,
            Provider: e.Provider,
            Model: e.ModelName,
            PromptId: e.PromptId,
            UseClipboardContext: e.UseClipboardContext,
            UseSelectedTextContext: e.UseSelectedTextContext,
            UseWindowContext: e.UseWindowContext,
            Output: OutputMode.Paste,
            CustomCommand: null,
            SendKey: config.Output.SendKey);
        if (mode is null)
        {
            return r;
        }

        r = r with { ModeName = mode.Name };
        if (mode.Language is { } lang)
        {
            r = r with
            {
                Language = !string.IsNullOrWhiteSpace(lang) && !lang.Equals("auto", StringComparison.OrdinalIgnoreCase)
                    ? lang.Trim()
                    : null,
            };
        }

        if (mode.TextFormatting is { } formatting) r = r with { TextFormatting = formatting };
        if (mode.EnhancementEnabled is { } enabled) r = r with { EnhancementEnabled = enabled };
        if (mode.EnhancementProvider is { } provider) r = r with { Provider = provider, Model = provider.DefaultModel() };
        if (!string.IsNullOrWhiteSpace(mode.EnhancementModel)) r = r with { Model = mode.EnhancementModel };
        if (mode.PromptId is { } id && config.Prompt(id) is not null) r = r with { PromptId = id };
        if (mode.UseClipboardContext is { } clip) r = r with { UseClipboardContext = clip };
        if (mode.UseSelectedTextContext is { } sel) r = r with { UseSelectedTextContext = sel };
        if (mode.SendKey is { } key) r = r with { SendKey = key };
        return r with
        {
            Output = mode.Output,
            CustomCommand = string.IsNullOrWhiteSpace(mode.CustomCommand) ? null : mode.CustomCommand,
        };
    }

    private static readonly char[] TriggerPunct = [',', '.', '!', '?', ';', ':'];

    /// <summary>
    /// Finds a mode trigger word at the start or end of <paramref name="text"/> and strips it.
    /// Longer trigger words win, then earlier modes, then earlier words.
    /// </summary>
    public static TriggerDetection? DetectTrigger(string text, IReadOnlyList<ModeConfig> modes)
    {
        var candidates = new List<(int Mode, int Word, string Text)>();
        for (var mi = 0; mi < modes.Count; mi++)
        {
            if (!modes[mi].Enabled) continue;
            for (var wi = 0; wi < modes[mi].TriggerWords.Count; wi++)
            {
                var w = modes[mi].TriggerWords[wi].Trim();
                if (w.Length > 0) candidates.Add((mi, wi, w));
            }
        }

        foreach (var (mode, _, word) in candidates
                     .OrderByDescending(c => c.Text.Length)
                     .ThenBy(c => c.Mode)
                     .ThenBy(c => c.Word))
        {
            string? processed;
            var trailing = StripTrailing(text, word);
            if (trailing is not null)
            {
                processed = StripLeading(trailing, word) ?? trailing;
            }
            else
            {
                var leading = StripLeading(text, word);
                if (leading is null) continue;
                processed = StripTrailing(leading, word) ?? leading;
            }

            return new TriggerDetection(mode, processed);
        }

        return null;
    }

    private static string CapitalizeFirst(string s)
    {
        if (s.Length == 0) return s;
        var first = char.IsSurrogate(s[0]) && s.Length > 1 ? s[..2] : s[..1];
        return first.ToUpperInvariant() + s[first.Length..];
    }

    private static string? StripLeading(string text, string word)
    {
        var trimmed = text.Trim();
        if (!trimmed.StartsWith(word, StringComparison.OrdinalIgnoreCase)) return null;
        var end = word.Length;
        if (end < trimmed.Length && char.IsLetterOrDigit(trimmed[end])) return null;
        var rest = TrimLeadingMixed(trimmed[end..]);
        return CapitalizeFirst(rest.Trim());
    }

    private static string? StripTrailing(string text, string word)
    {
        var trimmed = text.Trim().TrimEnd(TriggerPunct);
        if (!trimmed.EndsWith(word, StringComparison.OrdinalIgnoreCase)) return null;
        var start = trimmed.Length - word.Length;
        if (start > 0 && char.IsLetterOrDigit(trimmed[start - 1])) return null;
        var rest = TrimTrailingMixed(trimmed[..start]);
        return CapitalizeFirst(rest.Trim());
    }

    private static bool IsTrigger(char c) => char.IsWhiteSpace(c) || Array.IndexOf(TriggerPunct, c) >= 0;

    private static string TrimLeadingMixed(string s)
    {
        var i = 0;
        while (i < s.Length && IsTrigger(s[i])) i++;
        return s[i..];
    }

    private static string TrimTrailingMixed(string s)
    {
        var i = s.Length;
        while (i > 0 && IsTrigger(s[i - 1])) i--;
        return s[..i];
    }
}
