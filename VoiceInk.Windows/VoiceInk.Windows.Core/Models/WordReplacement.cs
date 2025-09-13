namespace VoiceInk.Windows.Core.Models
{
    /// <summary>
    /// Represents a single word or phrase replacement rule.
    /// </summary>
    public class WordReplacement
    {
        /// <summary>
        /// The text to find in the transcription output.
        /// </summary>
        public string Find { get; set; } = string.Empty;

        /// <summary>
        /// The text to replace the 'Find' text with.
        /// </summary>
        public string ReplaceWith { get; set; } = string.Empty;
    }
}
