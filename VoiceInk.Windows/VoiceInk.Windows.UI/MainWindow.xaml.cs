using System;
using System.ComponentModel;
using System.IO;
using System.Text;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Input;
using VoiceInk.Windows.Services;
using Whisper.net;
using Whisper.net.Ggml;

namespace VoiceInk.Windows.UI
{
    public partial class MainWindow : Window
    {
        private HotkeyService? _hotkeyService;
        private AudioService? _audioService;
        private readonly SettingsService _settingsService;
        private readonly DictionaryService _dictionaryService;
        private bool _isRecording = false;
        private Views.FloatingRecorderWindow? _floatingWindow;

        public ICommand ShowWindowCommand { get; }

        public MainWindow()
        {
            InitializeComponent();
            _settingsService = SettingsService.Instance;
            _dictionaryService = new DictionaryService(_settingsService);

            Loaded += MainWindow_Loaded;
            Closing += MainWindow_Closing;

            ShowWindowCommand = new RelayCommand(ShowWindow);
            DataContext = this;
        }

        private void MainWindow_Loaded(object sender, RoutedEventArgs e)
        {
            try
            {
                _hotkeyService = new HotkeyService(this);
                _hotkeyService.Register(HotkeyService.ModifierKeys.Control | HotkeyService.ModifierKeys.Shift, 0x52, ToggleRecording);
                TranscriptionOutput.Text = "Press 'Record' or Ctrl+Shift+R to start...";
            }
            catch (Exception ex)
            {
                MessageBox.Show($"Failed to register hotkey: {ex.Message}", "Error");
            }
        }

        private void MainWindow_Closing(object? sender, CancelEventArgs e)
        {
            e.Cancel = true;
            this.Hide();
        }

        private void RecordButton_Click(object sender, RoutedEventArgs e) => ToggleRecording();
        private void Record_Click(object sender, RoutedEventArgs e) => ToggleRecording();
        private void StopButton_Click(object sender, RoutedEventArgs e) => ToggleRecording();

        private void ToggleRecording()
        {
            if (!_isRecording)
            {
                // Start Recording
                _isRecording = true;
                RecordButton.IsEnabled = false;
                StopButton.IsEnabled = true;
                TranscriptionOutput.Text = "Recording...";

                _floatingWindow = new Views.FloatingRecorderWindow();
                _floatingWindow.Show();

                _audioService = new AudioService();
                _audioService.RecordingStopped += OnRecordingStopped;
                _audioService.StartRecording(_settingsService.Settings.AudioInputDeviceId);
            }
            else
            {
                // Stop Recording
                if (_audioService == null) return;

                _isRecording = false;
                TranscriptionOutput.Text = "Stopping and preparing to transcribe...";
                StopButton.IsEnabled = false;

                _floatingWindow?.Close();
                _floatingWindow = null;

                _audioService.StopRecording();
            }
        }

        private async void OnRecordingStopped(object? sender, DataAvailableEventArgs e)
        {
            await TranscribeAudio(e.AudioStream);

            if (sender is AudioService service)
            {
                service.Dispose();
                _audioService = null;
            }
        }

        private async Task TranscribeAudio(MemoryStream audioStream)
        {
            try
            {
                Dispatcher.Invoke(() => { ProgressBar.IsIndeterminate = true; });

                var modelName = _settingsService.Settings.ModelName;
                if (!File.Exists(modelName))
                {
                    Dispatcher.Invoke(() => TranscriptionOutput.Text = $"Downloading model '{modelName}'...");
                    using var modelFileStream = await WhisperGgmlDownloader.Default.GetGgmlModelAsync(GgmlType.Base, QuantizationType.Q5_1, true);
                    using var fileWriter = File.OpenWrite(modelName);
                    await modelFileStream.CopyToAsync(fileWriter);
                }

                using var whisperFactory = WhisperFactory.FromPath(modelName);

                var processorBuilder = whisperFactory.CreateBuilder()
                    .WithLanguage(_settingsService.Settings.Language);

                var currentPrompt = App.PowerModeService?.CurrentPrompt;
                if (!string.IsNullOrEmpty(currentPrompt))
                {
                    processorBuilder.WithPrompt(currentPrompt);
                    Debug.WriteLine($"Using Power Mode prompt: {currentPrompt}");
                }

                using var processor = processorBuilder.Build();

                audioStream.Position = 0;
                var transcriptionBuilder = new StringBuilder();

                Dispatcher.Invoke(() => TranscriptionOutput.Text = "Transcribing audio...");

                await foreach (var result in processor.ProcessAsync(audioStream))
                {
                    transcriptionBuilder.AppendLine(result.Text);
                }

                var final_text = transcriptionBuilder.ToString();
                var replaced_text = _dictionaryService.ApplyReplacements(final_text);

                Dispatcher.Invoke(() =>
                {
                    TranscriptionOutput.Text = replaced_text.Length > 0 ? replaced_text : "No text transcribed.";
                });
            }
            catch (Exception ex)
            {
                MessageBox.Show($"An error occurred during transcription: {ex.Message}", "Error", MessageBoxButton.OK, MessageBoxImage.Error);
                Dispatcher.Invoke(() => TranscriptionOutput.Text = "An error occurred. Please see the error message.");
            }
            finally
            {
                Dispatcher.Invoke(() =>
                {
                    ProgressBar.IsIndeterminate = false;
                    RecordButton.IsEnabled = true;
                    StopButton.IsEnabled = false;
                });
            }
        }

        private Views.SettingsWindow? _settingsWindow;
        private void Settings_Click(object sender, RoutedEventArgs e)
        {
            if (_settingsWindow == null || !_settingsWindow.IsLoaded)
            {
                _settingsWindow = new Views.SettingsWindow();
                _settingsWindow.Closed += (s, args) => _settingsWindow = null;
                _settingsWindow.Show();
            }
            else
            {
                _settingsWindow.Activate();
            }
        }

        private void Quit_Click(object sender, RoutedEventArgs e)
        {
            _hotkeyService?.Dispose();
            TrayIcon.Dispose();
            Application.Current.Shutdown();
        }

        private void ShowWindow()
        {
            this.Show();
            this.WindowState = WindowState.Normal;
            this.Activate();
        }
    }
}
