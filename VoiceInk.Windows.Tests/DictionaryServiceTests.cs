using VoiceInk.Windows.Core.Models;
using VoiceInk.Windows.Services;
using Xunit;
using Moq;
using System.Collections.Generic;

namespace VoiceInk.Windows.Tests
{
    public class DictionaryServiceTests
    {
        [Fact]
        public void ApplyReplacements_GivenTextWithMatchingRule_ReturnsReplacedText()
        {
            // Arrange
            var mockSettings = new AppSettings
            {
                WordReplacements = new List<WordReplacement>
                {
                    new WordReplacement { Find = "voicink", ReplaceWith = "VoiceInk" },
                    new WordReplacement { Find = "test", ReplaceWith = "production" }
                }
            };

            var mockSettingsService = new Mock<SettingsService>();
            // Since SettingsService is a singleton, this is a bit tricky.
            // A better design would use DI, but for this test, we can work around it
            // by not using the singleton instance and passing a mock.
            // We can't mock the `Settings` property easily as it has a private setter.
            // So we'll test the service's logic directly.
            // For a real app, we'd refactor SettingsService to be interface-based.

            var dictionaryService = new DictionaryService(mockSettingsService.Object);

            // Let's simulate the settings by creating a service that would have them.
            // This highlights a limitation of the current singleton design for testing.
            // A better test would use an interface ISettingsService.
            // For now, let's just test the logic with a direct instantiation.

            var settings = new AppSettings();
            settings.WordReplacements.Add(new WordReplacement { Find = "voicink", ReplaceWith = "VoiceInk" });

            // To properly test, we'd need to refactor SettingsService or test the logic more directly.
            // Let's assume we can create a temporary SettingsService for the test.
            // Given the current structure, let's just test the logic directly.

            var service = new DictionaryService(SettingsService.Instance); // Using the real singleton for this test
            SettingsService.Instance.Settings.WordReplacements.Clear();
            SettingsService.Instance.Settings.WordReplacements.Add(new WordReplacement { Find = "voicink", ReplaceWith = "VoiceInk" });

            var inputText = "welcome to voicink";
            var expectedText = "welcome to VoiceInk";

            // Act
            var result = service.ApplyReplacements(inputText);

            // Assert
            Assert.Equal(expectedText, result);

            // Cleanup
            SettingsService.Instance.Settings.WordReplacements.Clear();
        }
    }
}
