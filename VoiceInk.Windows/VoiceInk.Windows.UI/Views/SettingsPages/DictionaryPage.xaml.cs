using System.Collections.ObjectModel;
using System.Windows;
using System.Windows.Controls;
using VoiceInk.Windows.Core.Models;
using VoiceInk.Windows.Services;

namespace VoiceInk.Windows.UI.Views.SettingsPages
{
    public partial class DictionaryPage : Page
    {
        private readonly SettingsService _settingsService;
        public ObservableCollection<WordReplacement> WordReplacements { get; set; }

        public DictionaryPage()
        {
            InitializeComponent();
            DataContext = this;

            _settingsService = SettingsService.Instance;

            // Use an ObservableCollection to wrap the list from settings.
            // This allows the DataGrid to automatically update when items are added or removed.
            WordReplacements = new ObservableCollection<WordReplacement>(_settingsService.Settings.WordReplacements);
        }

        private void AddButton_Click(object sender, RoutedEventArgs e)
        {
            var findText = FindTextBox.Text;
            var replaceWithText = ReplaceWithTextBox.Text;

            if (string.IsNullOrWhiteSpace(findText))
            {
                MessageBox.Show("The 'Find' field cannot be empty.", "Validation Error");
                return;
            }

            var newReplacement = new WordReplacement { Find = findText, ReplaceWith = replaceWithText };

            // Add to the observable collection, which updates the UI
            WordReplacements.Add(newReplacement);
            // Also add to the underlying settings list
            _settingsService.Settings.WordReplacements.Add(newReplacement);

            // Clear the textboxes
            FindTextBox.Clear();
            ReplaceWithTextBox.Clear();
        }

        private void DeleteButton_Click(object sender, RoutedEventArgs e)
        {
            if (ReplacementsGrid.SelectedItem is WordReplacement selectedReplacement)
            {
                WordReplacements.Remove(selectedReplacement);
                _settingsService.Settings.WordReplacements.Remove(selectedReplacement);
            }
            else
            {
                MessageBox.Show("Please select a replacement to delete.", "No Selection");
            }
        }
    }
}
