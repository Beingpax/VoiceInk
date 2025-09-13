using System;
using System.IO;
using System.Text;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Input;
using NAudio.Wave;
using VoiceInkPoC.Services;
using Whisper.net;
using Whisper.net.Ggml;

namespace VoiceInkPoC
{
    public partial class MainWindow : Window
    {
        private WaveInEvent? _waveIn;
        private MemoryStream? _recordedAudioStream;
        private HotkeyService? _hotkeyService;
        private bool _isRecording = false;
        private const string ModelName = "ggml-base.en.bin";

        public MainWindow()
        {
            InitializeComponent();
            Loaded += MainWindow_Loaded;
            Closed += MainWindow_Closed;
        }

        private void MainWindow_Loaded(object sender, RoutedEventArgs e)
        {
            try
            {
                _hotkeyService = new HotkeyService(this);
                // Register Ctrl+Shift+R as the global hotkey to toggle recording.
                // 0x52 is the virtual key code for 'R'.
                _hotkeyService.Register(HotkeyService.ModifierKeys.Control | HotkeyService.ModifierKeys.Shift, 0x52, ToggleRecording);
                TranscriptionOutput.Text = "Press 'Record' or Ctrl+Shift+R to start...";
            }
            catch (Exception ex)
            {
                MessageBox.Show($"Failed to register hotkey: {ex.Message}", "Error");
            }
        }

        private void MainWindow_Closed(object? sender, EventArgs e)
        {
            // Clean up the hotkey service when the window closes.
            _hotkeyService?.Dispose();
        }

        private void RecordButton_Click(object sender, RoutedEventArgs e)
        {
            ToggleRecording();
        }

        private void StopButton_Click(object sender, RoutedEventArgs e)
        {
            ToggleRecording();
        }

        private void ToggleRecording()
        {
            if (!_isRecording)
            {
                StartRecording();
            }
            else
            {
                StopRecording();
            }
        }

        private void StartRecording()
        {
            _isRecording = true;
            RecordButton.IsEnabled = false;
            StopButton.IsEnabled = true;
            TranscriptionOutput.Text = "Recording...";

            _waveIn = new WaveInEvent { WaveFormat = new WaveFormat(16000, 16, 1) };
            _recordedAudioStream = new MemoryStream();
            _waveIn.DataAvailable += (s, args) => _recordedAudioStream.Write(args.Buffer, 0, args.BytesRecorded);
            _waveIn.RecordingStopped += async (s, args) =>
            {
                if (_recordedAudioStream != null)
                {
                    await TranscribeAudio();
                    _recordedAudioStream.Dispose();
                    _recordedAudioStream = null;
                }
                _waveIn?.Dispose();
                _waveIn = null;
            };
            _waveIn.StartRecording();
        }

        private void StopRecording()
        {
            _isRecording = false;
            TranscriptionOutput.Text = "Stopping and preparing to transcribe...";
            StopButton.IsEnabled = false;
            _waveIn?.StopRecording();
        }

        private async Task TranscribeAudio()
        {
            try
            {
                Dispatcher.Invoke(() =>
                {
                    TranscriptionOutput.Text = "Initializing transcription engine...";
                    ProgressBar.IsIndeterminate = true;
                });

                // 1. Download the Whisper model if it doesn't exist.
                if (!File.Exists(ModelName))
                {
                    Dispatcher.Invoke(() => TranscriptionOutput.Text = $"Downloading model '{ModelName}'...");
                    using var modelStream = await WhisperGgmlDownloader.Default.GetGgmlModelAsync(GgmlType.Base, QuantizationType.Q5_1, true);
                    using var fileWriter = File.OpenWrite(ModelName);
                    await modelStream.CopyToAsync(fileWriter);
                }

                // 2. Initialize the WhisperFactory and the processor.
                using var whisperFactory = WhisperFactory.FromPath(ModelName);
                using var processor = whisperFactory.CreateBuilder()
                    .WithLanguage("en") // Or "auto" for language detection
                    .Build();

                // 3. Process the audio stream.
                _recordedAudioStream.Position = 0; // Rewind the stream to the beginning.
                var transcriptionBuilder = new StringBuilder();

                Dispatcher.Invoke(() => TranscriptionOutput.Text = "Transcribing audio...");

                await foreach (var result in processor.ProcessAsync(_recordedAudioStream))
                {
                    transcriptionBuilder.AppendLine(result.Text);
                    // You can optionally update the UI in real-time here
                    // Dispatcher.Invoke(() => TranscriptionOutput.Text = transcriptionBuilder.ToString());
                }

                Dispatcher.Invoke(() =>
                {
                    TranscriptionOutput.Text = transcriptionBuilder.Length > 0 ? transcriptionBuilder.ToString() : "No text transcribed.";
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
    }
}
