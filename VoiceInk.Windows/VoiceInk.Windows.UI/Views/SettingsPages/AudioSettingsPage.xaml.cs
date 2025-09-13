using System.Linq;
using System.Windows;
using System.Windows.Controls;
using VoiceInk.Windows.Services;

namespace VoiceInk.Windows.UI.Views.SettingsPages
{
    public partial class AudioSettingsPage : Page
    {
        private readonly AudioService _audioService;
        private readonly SettingsService _settingsService;

        public AudioSettingsPage()
        {
            InitializeComponent();
            _audioService = new AudioService();
            _settingsService = SettingsService.Instance;

            Loaded += AudioSettingsPage_Loaded;
        }

        private void AudioSettingsPage_Loaded(object sender, RoutedEventArgs e)
        {
            LoadDevices();
        }

        private void LoadDevices()
        {
            var devices = _audioService.GetInputDevices().ToList();
            DeviceComboBox.ItemsSource = devices;

            // Load the saved setting and select the correct device
            var savedDeviceId = _settingsService.Settings.AudioInputDeviceId;
            var selectedDevice = devices.FirstOrDefault(d => d.Id == savedDeviceId);
            if (selectedDevice != null)
            {
                DeviceComboBox.SelectedItem = selectedDevice;
            }
            else if (devices.Any())
            {
                DeviceComboBox.SelectedIndex = 0;
            }
        }

        private void DeviceComboBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            if (DeviceComboBox.SelectedItem is AudioDevice selectedDevice)
            {
                // Save the selected device ID to settings
                _settingsService.Settings.AudioInputDeviceId = selectedDevice.Id;
                // No need to call SaveSettings() here, as it's called on application exit.
            }
        }
    }
}
