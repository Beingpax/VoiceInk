using System.Text;

namespace VoiceInk.Core.Text;

public static class ParagraphFormatter
{
    private const int TargetWordCount = 50;
    private const int MaxSentencesPerChunk = 4;
    private const int MinWordsForSignificantSentence = 4;

    /// <summary>
    /// Splits text into sentences on terminal punctuation followed by whitespace
    /// (or on CJK full-width terminators, which need no whitespace).
    /// </summary>
    public static List<string> SplitSentences(string text)
    {
        var sentences = new List<string>();
        var current = new StringBuilder();

        void Flush()
        {
            var trimmed = current.ToString().Trim();
            if (trimmed.Length > 0) sentences.Add(trimmed);
            current.Clear();
        }

        for (var i = 0; i < text.Length; i++)
        {
            var ch = text[i];
            current.Append(ch);
            var boundary = false;
            switch (ch)
            {
                case '。' or '！' or '？':
                    boundary = true;
                    break;
                case '.' or '!' or '?' or '…':
                    // Absorb closing quotes/brackets and repeated punctuation.
                    while (i + 1 < text.Length && text[i + 1] is '.' or '!' or '?' or '"' or '\'' or '”' or '’' or ')' or ']')
                    {
                        current.Append(text[++i]);
                    }

                    boundary = i + 1 >= text.Length || char.IsWhiteSpace(text[i + 1]);
                    break;
                case '\n':
                    boundary = true;
                    break;
            }

            if (boundary) Flush();
        }

        Flush();
        return sentences;
    }

    public static string Format(string text)
    {
        var sentences = SplitSentences(text);
        if (sentences.Count == 0) return "";

        var paragraphs = new List<string>();
        var index = 0;
        while (index < sentences.Count)
        {
            var tentative = new List<string>();
            var words = 0;
            var significant = 0;
            foreach (var sentence in sentences.Skip(index))
            {
                var n = Words.Count(sentence);
                tentative.Add(sentence);
                words += n;
                if (n >= MinWordsForSignificantSentence) significant++;
                if (words >= TargetWordCount) break;
            }

            List<string> chunk;
            if (significant > MaxSentencesPerChunk)
            {
                chunk = [];
                var counted = 0;
                foreach (var sentence in tentative)
                {
                    chunk.Add(sentence);
                    if (Words.Count(sentence) >= MinWordsForSignificantSentence)
                    {
                        counted++;
                        if (counted >= MaxSentencesPerChunk) break;
                    }
                }
            }
            else
            {
                chunk = tentative;
            }

            if (chunk.Count == 0) break;
            index += chunk.Count;
            paragraphs.Add(string.Join(' ', chunk));
        }

        return string.Join("\n\n", paragraphs).Trim();
    }
}
