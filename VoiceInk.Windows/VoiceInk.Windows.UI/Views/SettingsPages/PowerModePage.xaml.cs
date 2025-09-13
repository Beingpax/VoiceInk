using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Controls;
using VoiceInk.Windows.Core.Models;
using VoiceInk.Windows.Services;

namespace VoiceInk.Windows.UI.Views.SettingsPages
{
    public partial class PowerModePage : Page, INotifyPropertyChanged
    {
        private readonly SettingsService _settingsService;

        public ObservableCollection<PowerModeRule> PowerModeRules { get; set; }
        public List<ConditionType> ConditionTypes { get; }
        public List<ConditionOperator> ConditionOperators { get; }

        private PowerModeRule _newRule;
        public PowerModeRule NewRule
        {
            get => _newRule;
            set { _newRule = value; OnPropertyChanged(); }
        }

        public PowerModePage()
        {
            InitializeComponent();
            DataContext = this;

            _settingsService = SettingsService.Instance;

            PowerModeRules = new ObservableCollection<PowerModeRule>(_settingsService.Settings.PowerModeRules);
            ConditionTypes = Enum.GetValues(typeof(ConditionType)).Cast<ConditionType>().ToList();
            ConditionOperators = Enum.GetValues(typeof(ConditionOperator)).Cast<ConditionOperator>().ToList();

            NewRule = new PowerModeRule();
        }

        private void AddButton_Click(object sender, RoutedEventArgs e)
        {
            if (string.IsNullOrWhiteSpace(NewRule.ConditionValue) || string.IsNullOrWhiteSpace(NewRule.Prompt))
            {
                MessageBox.Show("Please fill out all fields for the new rule.", "Validation Error");
                return;
            }

            var ruleToAdd = new PowerModeRule
            {
                ConditionType = NewRule.ConditionType,
                ConditionOperator = NewRule.ConditionOperator,
                ConditionValue = NewRule.ConditionValue,
                Prompt = NewRule.Prompt
            };

            PowerModeRules.Add(ruleToAdd);
            _settingsService.Settings.PowerModeRules.Add(ruleToAdd);

            // Reset the 'new rule' object for the next entry
            NewRule = new PowerModeRule();
        }

        private void DeleteButton_Click(object sender, RoutedEventArgs e)
        {
            if (RulesGrid.SelectedItem is PowerModeRule selectedRule)
            {
                PowerModeRules.Remove(selectedRule);
                _settingsService.Settings.PowerModeRules.Remove(selectedRule);
            }
            else
            {
                MessageBox.Show("Please select a rule to delete.", "No Selection");
            }
        }

        public event PropertyChangedEventHandler? PropertyChanged;
        protected virtual void OnPropertyChanged([CallerMemberName] string? propertyName = null)
        {
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
        }
    }
}
