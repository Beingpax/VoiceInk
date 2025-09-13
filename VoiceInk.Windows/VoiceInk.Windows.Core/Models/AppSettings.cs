namespace VoiceInk.Windows.Core.Models
{
    /// <summary>
    /// Represents all user-configurable settings for the application.
    /// This class is serialized to and from JSON.
    /// </summary>
    public class AppSettings
    {
        /// <summary>
        /// The language to be used for transcription.
        /// Can be "auto" for automatic language detection.
        /// </summary>
        public string Language { get; set; } = "en";

        /// <summary>
        /// The name of the GGML model file to be used for transcription.
        /// e.g., "ggml-base.en.bin"
        /// </summary>
        public string ModelName { get; set; } = "ggml-base.en.bin";

        /// <summary>
        /// Determines whether the application should launch when the user logs into Windows.
        /// </summary>
        public bool LaunchAtLogin { get; set; } = false;

        /// <summary>
        /// The device ID of the selected audio input device.
        /// Default is 0, which is typically the system's default microphone.
        /// </summary>
        public int AudioInputDeviceId { get; set; } = 0;

        /// <summary>
        /// A list of custom word/phrase replacements to be applied to the final transcript.
        /// </summary>
        public List<WordReplacement> WordReplacements { get; set; } = new();

        /// <summary>
        /// A list of rules that define behavior for Power Mode.
        /// </summary>
        public List<PowerModeRule> PowerModeRules { get; set; } = new();

        /// <summary>
        /// A flag to indicate if the user has completed the first-run onboarding process.
        /// </summary>
        public bool HasCompletedOnboarding { get; set; } = false;
    }
}
