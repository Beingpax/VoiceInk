using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Linq;
using System.Runtime.CompilerServices;
using VoiceInk.Windows.Core.Models;

namespace VoiceInk.Windows.Services
{
    /// <summary>
    /// The engine for Power Mode. Evaluates rules based on the active window and determines the current context/prompt.
    /// </summary>
    public class PowerModeService : INotifyPropertyChanged
    {
        private readonly SettingsService _settingsService;
        private string _currentPrompt = string.Empty;

        public string CurrentPrompt
        {
            get => _currentPrompt;
            private set
            {
                if (_currentPrompt != value)
                {
                    _currentPrompt = value;
                    OnPropertyChanged();
                }
            }
        }

        public PowerModeService(SettingsService settingsService, WindowTrackingService windowTrackingService, BrowserUrlService browserUrlService)
        {
            _settingsService = settingsService;
            windowTrackingService.ActiveWindowChanged += (sender, args) => OnActiveWindowChanged(args, browserUrlService);
        }

        private void OnActiveWindowChanged(ActiveWindowChangedEventArgs args, BrowserUrlService browserUrlService)
        {
            var rules = _settingsService.Settings.PowerModeRules;
            if (!rules.Any())
            {
                CurrentPrompt = string.Empty;
                return;
            }

            browserUrlService.TryGetBrowserUrl(args.ActiveWindow.ProcessName, args.ActiveWindow.WindowHandle, out var url);

            // Find the first matching rule
            var matchedRule = rules.FirstOrDefault(rule => CheckRule(rule, args.ActiveWindow, url));

            CurrentPrompt = matchedRule?.Prompt ?? string.Empty;
            Debug.WriteLine($"Power Mode: Active prompt is now '{CurrentPrompt}'");
        }

        private bool CheckRule(PowerModeRule rule, ActiveWindowInfo windowInfo, string? url)
        {
            string? targetText = rule.ConditionType switch
            {
                ConditionType.ProcessName => windowInfo.ProcessName,
                ConditionType.WindowTitle => windowInfo.WindowTitle,
                ConditionType.BrowserUrl => url,
                _ => null
            };

            if (targetText == null) return false;

            return rule.ConditionOperator switch
            {
                ConditionOperator.Contains => targetText.Contains(rule.ConditionValue, StringComparison.OrdinalIgnoreCase),
                ConditionOperator.Equals => targetText.Equals(rule.ConditionValue, StringComparison.OrdinalIgnoreCase),
                ConditionOperator.StartsWith => targetText.StartsWith(rule.ConditionValue, StringComparison.OrdinalIgnoreCase),
                ConditionOperator.EndsWith => targetText.EndsWith(rule.ConditionValue, StringComparison.OrdinalIgnoreCase),
                _ => false
            };
        }

        public event PropertyChangedEventHandler? PropertyChanged;
        protected virtual void OnPropertyChanged([CallerMemberName] string? propertyName = null)
        {
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
        }
    }
}
