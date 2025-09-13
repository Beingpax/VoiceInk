namespace VoiceInk.Windows.Core.Models
{
    public enum ConditionType
    {
        ProcessName,
        WindowTitle,
        BrowserUrl
    }

    public enum ConditionOperator
    {
        Contains,
        Equals,
        StartsWith,
        EndsWith
    }

    /// <summary>
    /// Represents a single rule for the Power Mode feature.
    /// </summary>
    public class PowerModeRule
    {
        public ConditionType ConditionType { get; set; }
        public ConditionOperator ConditionOperator { get; set; }
        public string ConditionValue { get; set; } = string.Empty;

        // For now, the only action is to set a prompt. This could be expanded later.
        public string Prompt { get; set; } = string.Empty;
    }
}
