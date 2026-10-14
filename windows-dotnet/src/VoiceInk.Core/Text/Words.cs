using System.Text;

namespace VoiceInk.Core.Text;

public static class Words
{
    /// <summary>
    /// Counts words. Runs of letters/digits (plus inner apostrophes) are one word; CJK ideographs, kana and Thai
    /// count one word per character since those scripts do not separate words with spaces.
    /// </summary>
    public static int Count(string text)
    {
        var count = 0;
        var inWord = false;
        foreach (var rune in text.EnumerateRunes())
        {
            if (IsUnspacedScript(rune))
            {
                count++;
                inWord = false;
            }
            else if (Rune.IsLetter(rune) || Rune.IsNumber(rune) || (inWord && (rune.Value is '\'' or '’')))
            {
                if (!inWord)
                {
                    count++;
                    inWord = true;
                }
            }
            else
            {
                inWord = false;
            }
        }

        return count;
    }

    public static bool IsUnspacedScript(Rune r) => r.Value is
        (>= 0x3040 and <= 0x309F) or (>= 0x30A0 and <= 0x30FF) or (>= 0x4E00 and <= 0x9FFF)
        or (>= 0xAC00 and <= 0xD7AF) or (>= 0x0E00 and <= 0x0E7F);
}
