using System.Text.RegularExpressions;

namespace VoiceInk.Core.Text;

public static partial class TextFilter
{
    /// <summary>Same defaults as <c>FillerWordManager.defaultFillerWords</c>.</summary>
    public static readonly string[] DefaultFillerWords =
        ["uh", "um", "uhm", "umm", "uhh", "uhhh", "hmm", "hm", "mmm", "mm", "mh", "ehh"];

    // Removes `<tag ...>...</tag>` blocks; an opening tag without a closing tag stays.
    [GeneratedRegex(@"<([A-Za-z][A-Za-z0-9:_-]*)[^>]*>[\s\S]*?</\1>")]
    private static partial Regex TagBlock();

    [GeneratedRegex(@"\[.*?\]|\(.*?\)|\{.*?\}")]
    private static partial Regex Brackets();

    [GeneratedRegex(@"\s{2,}")]
    private static partial Regex Spaces();

    [GeneratedRegex(@"<thinking>[\s\S]*?</thinking>|<think>[\s\S]*?</think>|<reasoning>[\s\S]*?</reasoning>")]
    private static partial Regex Thinking();

    /// <summary>
    /// Cleans raw ASR output: strips tag blocks, bracketed hallucinations (<c>[MUSIC]</c>, <c>(laughs)</c>,
    /// <c>{noise}</c>), filler words and redundant whitespace.
    /// </summary>
    public static string FilterTranscription(string text, IEnumerable<string> fillerWords)
    {
        var filtered = TagBlock().Replace(text, "");
        filtered = Brackets().Replace(filtered, "");

        foreach (var word in fillerWords.Select(w => w.Trim()).Where(w => w.Length > 0))
        {
            var pattern = $@"\b{Regex.Escape(word)}\b[,.]?";
            filtered = Regex.Replace(filtered, pattern, "", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
        }

        filtered = Spaces().Replace(filtered, " ");
        return filtered.Trim();
    }

    /// <summary>Strips reasoning blocks that some LLMs emit before their answer.</summary>
    public static string FilterEnhancementOutput(string text) => Thinking().Replace(text, "").Trim();
}
