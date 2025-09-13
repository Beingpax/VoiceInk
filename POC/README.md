# VoiceInk for Windows - Proof of Concept

This folder contains a proof-of-concept (PoC) for the core functionality of a VoiceInk application on Windows. The goal of this PoC is to demonstrate how to record audio from a microphone and transcribe it to text using the `whisper.cpp` library.

## Core Technologies Used

*   **UI Framework:** WPF (Windows Presentation Foundation)
*   **Language:** C#
*   **Audio Recording:** `NAudio` - A popular and comprehensive audio library for .NET.
*   **Transcription:** `Whisper.net` - A .NET wrapper for the `whisper.cpp` library. It simplifies the process of using Whisper models in a .NET application by handling the native library loading and providing a high-level API.

## How to Build and Run this PoC

1.  **Create a New Project:**
    *   Open Visual Studio.
    *   Create a new **WPF Application** project.
    *   Name the project `VoiceInkPoC`.

2.  **Add NuGet Packages:**
    *   Right-click on your project in the Solution Explorer and select "Manage NuGet Packages...".
    *   Browse for and install the following packages:
        *   `NAudio`
        *   `Whisper.net`
        *   `Whisper.net.Runtime` (This package provides the native `whisper.dll` binaries).

3.  **Add the Code:**
    *   Replace the content of `MainWindow.xaml` with the code from [POC/MainWindow.xaml](./MainWindow.xaml).
    *   Replace the content of `MainWindow.xaml.cs` with the code from [POC/MainWindow.xaml.cs](./MainWindow.xaml.cs).

4.  **Run the Application:**
    *   Press F5 or click the "Start" button in Visual Studio.
    *   The first time you click "Record" and then "Stop & Transcribe", the application will automatically download the required Whisper model file (`ggml-base.en.bin`) into the `bin/Debug` folder of your project. This may take a few moments.
    *   Subsequent transcriptions will be much faster as the model will already be on disk.

## How it Works

1.  **Global Hotkey:** When the application starts, a `HotkeyService` is initialized. It registers a system-wide hotkey for `Ctrl+Shift+R`. This service listens for messages from Windows to detect when the hotkey is pressed.
2.  **Recording:** When the "Record" button is clicked or the `Ctrl+Shift+R` hotkey is pressed, the `ToggleRecording` method is called. The `NAudio` library starts capturing audio from the default microphone. The audio is captured in the format that Whisper expects (16kHz, 16-bit, mono) and is written into a `MemoryStream`.
3.  **Stopping:** When the "Stop & Transcribe" button is clicked or `Ctrl+Shift+R` is pressed again, the recording is stopped.
4.  **Transcription:**
    *   The `Whisper.net` library is initialized. It automatically checks if the model file exists and downloads it if necessary.
    *   A `WhisperProcessor` is created, configured for the English language.
    *   The `ProcessAsync` method is called, passing in the `MemoryStream` containing the recorded audio.
    *   `Whisper.net` processes the audio in the background and returns the transcribed text segments.
    *   The final text is displayed in the text box.

## Next Steps in Full Implementation

This PoC covers the core transcription and a key system integration (global hotkeys). A full rewrite would involve building out the remaining features from the macOS application, including:

*   A complete settings UI.
*   The "Power Mode" feature for context-aware settings.
*   Custom dictionary management.
*   A system tray icon for background operation.
