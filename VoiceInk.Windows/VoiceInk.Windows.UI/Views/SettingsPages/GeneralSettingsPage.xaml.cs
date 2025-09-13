using System.Windows.Controls;
using VoiceInk.Windows.Services;

namespace VoiceInk.Windows.UI.Views.SettingsPages
{
    public partial class GeneralSettingsPage : Page
    {
        public GeneralSettingsPage()
        {
            InitializeComponent();

            // Set the DataContext for the page to the settings object.
            // This allows the CheckBox's IsChecked property to bind directly to the LaunchAtLogin property.
            DataContext = SettingsService.Instance.Settings;
        }
    }
}
