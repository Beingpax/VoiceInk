using System;
using System.Windows;
using System.Windows.Controls;
using VoiceInk.Windows.UI.Views.SettingsPages;

namespace VoiceInk.Windows.UI.Views
{
    public partial class SettingsWindow : Window
    {
        public SettingsWindow()
        {
            InitializeComponent();
            // Select the first item by default
            NavigationListBox.SelectedIndex = 0;
        }

        private void NavigationListBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            if (e.AddedItems.Count > 0 && e.AddedItems[0] is ListBoxItem selectedItem)
            {
                Uri? pageUri = selectedItem.Content switch
                {
                    "General" => new Uri("SettingsPages/GeneralSettingsPage.xaml", UriKind.Relative),
                    "Audio" => new Uri("SettingsPages/AudioSettingsPage.xaml", UriKind.Relative),
                    "Models" => new Uri("SettingsPages/ModelSettingsPage.xaml", UriKind.Relative),
                    "Dictionary" => new Uri("SettingsPages/DictionaryPage.xaml", UriKind.Relative),
                    "Power Mode" => new Uri("SettingsPages/PowerModePage.xaml", UriKind.Relative),
                    _ => null
                };

                if (pageUri != null)
                {
                    SettingsFrame.Navigate(pageUri);
                }
            }
        }
    }
}
