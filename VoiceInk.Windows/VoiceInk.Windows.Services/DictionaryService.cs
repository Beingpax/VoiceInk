using System.Collections.Generic;
using System.Linq;
using VoiceInk.Windows.Core.Models;

namespace VoiceInk.Windows.Services
{
    /// <summary>
    /// A service to manage and apply dictionary word/phrase replacements.
    /// </summary>
    public class DictionaryService
    {
        private readonly SettingsService _settingsService;

        public DictionaryService(SettingsService settingsService)
        {
            _settingsService = settingsService;
        }

        /// <summary>
        /// Applies all configured word replacements to the input text.
        /// </summary>
        /// <param name="text">The original text.</param>
        /// <returns>The text with replacements applied.</returns>
        public string ApplyReplacements(string text)
        {
            var replacements = _settingsService.Settings.WordReplacements;
            if (replacements == null || !replacements.Any())
            {
                return text;
            }

            // A simple StringBuilder approach for replacements.
            // For very large numbers of replacements, a more advanced algorithm like Aho-Corasick might be considered.
            var result = text;
            foreach (var replacement in replacements)
            {
                if (!string.IsNullOrEmpty(replacement.Find))
                {
                    result = result.Replace(replacement.Find, replacement.ReplaceWith, System.StringComparison.OrdinalIgnoreCase);
                }
            }
            return result;
        }
    }
}
