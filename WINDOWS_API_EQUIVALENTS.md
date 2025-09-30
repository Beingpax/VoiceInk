# Windows API Equivalents for macOS Functionalities (WPF/C#)

This document outlines Windows API equivalents and .NET library recommendations for macOS audio functionalities, targeting a WPF/C# environment.

## 1. Audio Input

This section details how to enumerate audio input devices and record audio, similar to functionalities that might be found in `AudioDeviceManager.swift` and `Recorder.swift` on macOS.

### Recommended Approach: NAudio Library

Using the **NAudio library** is highly recommended for WPF/C# applications. It's a powerful open-source .NET audio library that provides managed wrappers around Windows Core Audio APIs (including WASAPI and WaveIn/Out), simplifying development significantly.

*   **Installation:** Add NAudio via NuGet Package Manager: `Install-Package NAudio`

### a. Enumerating Audio Input Devices

*   **Functionality:** Listing available microphones or other audio input sources.
*   **macOS Equivalent:** `AudioDeviceManager.swift` enumerating devices.
*   **Windows API (Low-Level):**
    *   Utilizes the `MMDevice API` (part of Core Audio).
    *   Key interface: `IMMDeviceEnumerator`.
    *   Steps involve creating an enumerator, getting a collection of audio endpoints (specifying `eCapture` for input devices), and querying properties of each `IMMDevice`.
*   **NAudio (Recommended for C#):**
    *   Use `NAudio.CoreAudioApi.MMDeviceEnumerator` to list devices.
    *   Filter for `DataFlow.Capture` and `DeviceState.Active`.
    *   Each device is represented as an `MMDevice` object, which has properties like `FriendlyName`.

    ```csharp
    // C# Example using NAudio
    using NAudio.CoreAudioApi;
    using System.Linq;

    public List<MMDevice> GetInputDevices()
    {
        var enumerator = new MMDeviceEnumerator();
        // List active capture devices (microphones)
        return enumerator.EnumerateAudioEndPoints(DataFlow.Capture, DeviceState.Active).ToList();
    }

    // In your UI (e.g., Window_Loaded or ViewModel constructor):
    // var inputDevices = GetInputDevices();
    // myComboBox.ItemsSource = inputDevices; // Assuming myComboBox is a ComboBox
    // myComboBox.DisplayMemberPath = "FriendlyName";
    ```

### b. Recording Audio from a Selected Device

*   **Functionality:** Capturing audio data from a chosen input device.
*   **macOS Equivalent:** `Recorder.swift` handling the recording process.
*   **Windows API (WASAPI - Low-Level):**
    *   Involves `IAudioClient` and `IAudioCaptureClient` interfaces.
    *   Requires manual buffer management, format negotiation, and COM interop.
    *   Key steps: Activate `IAudioClient` on an `IMMDevice`, initialize it (shared or exclusive mode), get `IAudioCaptureClient`, start the client, and then loop to read data using `GetBuffer` and `ReleaseBuffer`.
*   **NAudio (Recommended for C#):**
    *   **`NAudio.Wave.WasapiCapture`:** Modern API for capturing audio using WASAPI. Preferred for most scenarios.
    *   **`NAudio.Wave.WaveInEvent` or `WaveIn`:** Older WaveIn API, can also be used. `WaveInEvent` is generally easier for UI applications as its event fires on the UI thread (or a synchronizable context).

    ```csharp
    // C# Example using NAudio.Wave.WasapiCapture
    using NAudio.Wave;
    using NAudio.CoreAudioApi; // For MMDevice if selecting non-default

    public class AudioRecorder : IDisposable
    {
        private WasapiCapture capture;
        private WaveFileWriter writer;
        private string outputFilePath;
        public bool IsRecording { get; private set; }

        // Constructor for default device
        public AudioRecorder() { }

        // Constructor for a specific device
        // public AudioRecorder(MMDevice device)
        // {
        //     // Note: WasapiCapture can take MMDevice in some constructors or use default
        // }

        public void StartRecording(string outputPath, MMDevice device = null)
        {
            if (IsRecording) return;

            outputFilePath = outputPath;

            if (device == null)
            {
                capture = new WasapiCapture(); // Uses default capture device
            }
            else
            {
                capture = new WasapiCapture(device); // Uses specified device
            }

            writer = new WaveFileWriter(outputFilePath, capture.WaveFormat);

            capture.DataAvailable += (s, e) =>
            {
                writer.Write(e.Buffer, 0, e.BytesRecorded);
                // Optional: Process raw bytes 'e.Buffer' for real-time analysis
            };

            capture.RecordingStopped += (s, e) =>
            {
                writer?.Dispose();
                writer = null;
                capture?.Dispose(); // Dispose of capture object itself
                capture = null;
                IsRecording = false;
                // Handle recording stopped (e.g., UI updates, file processing)
                if (e.Exception != null)
                {
                    // Handle error
                    Console.WriteLine($"Error during recording: {e.Exception.Message}");
                }
            };

            capture.StartRecording();
            IsRecording = true;
        }

        public void StopRecording()
        {
            if (!IsRecording || capture == null) return;
            capture.StopRecording(); // This will trigger the RecordingStopped event
        }

        public void Dispose()
        {
            StopRecording(); // Ensure resources are released
            writer?.Dispose();
            capture?.Dispose();
        }
    }
    ```

## 2. Basic UI Elements (WPF/C#)

WPF provides a rich set of UI elements through XAML and C#. The following are standard controls for an initial transcription UI.

### a. Button for Start/Stop Recording

*   **XAML:**
    ```xml
    <Button x:Name="RecordButton" Content="Start Recording" Click="RecordButton_Click"/>
    ```
*   **C# (Code-behind or ViewModel Command):**
    ```csharp
    // Assuming an instance of the AudioRecorder class from above
    // private AudioRecorder audioRecorder = new AudioRecorder();
    // private bool isCurrentlyRecording = false;
    // private MMDevice selectedAudioDevice; // Populated from ComboBox

    private void RecordButton_Click(object sender, RoutedEventArgs e)
    {
        if (!isCurrentlyRecording)
        {
            // string outputWaveFile = "recording.wav"; // Define your output path
            // audioRecorder.StartRecording(outputWaveFile, selectedAudioDevice);
            // RecordButton.Content = "Stop Recording";
            isCurrentlyRecording = true;
        }
        else
        {
            // audioRecorder.StopRecording();
            // RecordButton.Content = "Start Recording";
            isCurrentlyRecording = false;
        }
    }
    ```

### b. Text Display Area for Transcriptions

*   **XAML:**
    ```xml
    <TextBox x:Name="TranscriptionDisplay"
             TextWrapping="Wrap"
             AcceptsReturn="True"
             IsReadOnly="True"
             VerticalScrollBarVisibility="Auto"
             Height="200"/>
    ```
*   **C# (Updating the TextBox):**
    ```csharp
    // To set text:
    // TranscriptionDisplay.Text = "Your transcription here...";
    // To append text (ensure UI thread for updates from non-UI threads):
    // Application.Current.Dispatcher.Invoke(() =>
    // {
    //     TranscriptionDisplay.AppendText("New segment...\n");
    // });
    ```

### c. Dropdown/List for Audio Input Device Selection

*   **XAML:**
    ```xml
    <ComboBox x:Name="AudioDeviceSelector"
              DisplayMemberPath="FriendlyName"
              SelectionChanged="AudioDeviceSelector_SelectionChanged"
              Margin="0,0,0,10"/>
    ```
*   **C# (Populating and Handling Selection):**
    ```csharp
    // using NAudio.CoreAudioApi;
    // using System.Collections.Generic;
    // using System.Linq;

    // private MMDevice selectedAudioDevice;

    // public void LoadAudioInputDevices()
    // {
    //     var enumerator = new MMDeviceEnumerator();
    //     var devices = enumerator.EnumerateAudioEndPoints(DataFlow.Capture, DeviceState.Active).ToList();
    //     AudioDeviceSelector.ItemsSource = devices;

    //     if (AudioDeviceSelector.Items.Count > 0)
    //     {
    //         AudioDeviceSelector.SelectedIndex = 0; // Select first device by default
    //         selectedAudioDevice = (MMDevice)AudioDeviceSelector.SelectedItem;
    //     }
    // }

    // private void AudioDeviceSelector_SelectionChanged(object sender, SelectionChangedEventArgs e)
    // {
    //     if (AudioDeviceSelector.SelectedItem != null)
    //     {
    //         selectedAudioDevice = (MMDevice)AudioDeviceSelector.SelectedItem;
    //     }
    // }

    // Call LoadAudioInputDevices() in your window's constructor or Loaded event.
    ```

### Specific Considerations for WPF UI:

*   **Thread Safety:** Audio data callbacks (e.g., NAudio's `DataAvailable`) usually run on a separate thread. All UI updates must be marshaled to the UI thread using `Dispatcher.Invoke` or `Dispatcher.BeginInvoke`.
*   **Resource Management:** Properly dispose of NAudio objects (like `WasapiCapture`, `WaveFileWriter`) when they are no longer needed (e.g., in `Dispose` methods, window closing events, or after recording stops). The provided `AudioRecorder` class includes a basic `Dispose` pattern.
*   **MVVM Pattern:** For more complex applications, consider using the Model-View-ViewModel (MVVM) pattern to separate concerns. UI interactions (like button clicks) would be handled by Commands in the ViewModel, and data (like the list of audio devices or the transcription text) would be exposed through bindable properties.
*   **Error Handling:** Implement robust error handling for scenarios like no microphone detected, device access errors, etc.
*   **Application Permissions:** Ensure your application has microphone permissions if targeting recent Windows versions. Usually, the OS handles user prompts.

This summary provides a starting point for implementing audio input and basic UI for a transcription application in WPF/C#. NAudio greatly simplifies the audio aspects compared to direct Windows API calls.
