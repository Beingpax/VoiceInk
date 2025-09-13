# VoiceInk for Windows - Proof of Concept Project

This directory contains a complete, runnable Visual Studio project that serves as a proof-of-concept (PoC) for a Windows version of the VoiceInk application.

The goal of this PoC is to provide a solid foundation for the full application by demonstrating the core transcription functionality and key system integrations using a modern .NET technology stack.

## Features Demonstrated

*   **Core Transcription:** Audio is captured from the microphone and transcribed to text using the `whisper.cpp` engine.
*   **Global Hotkey:** A system-wide hotkey (`Ctrl+Shift+R`) is registered to start and stop recording from any application.
*   **Ready-to-Run Project:** The project is structured as a standard Visual Studio solution, ready to be opened and run with minimal effort.

## Technology Stack

*   **UI Framework:** WPF (Windows Presentation Foundation) on .NET 8.
*   **Language:** C#
*   **Audio Recording:** `NAudio` - A popular and comprehensive audio library for .NET.
*   **Transcription:** `Whisper.net` - A high-level .NET wrapper for the `whisper.cpp` library. It handles the native library loading and provides a simple API for transcription.

## How to Run the Application

This project is designed to be as simple as possible to run for a developer with a standard Windows setup.

### Prerequisites

*   Windows 10 or 11.
*   Visual Studio 2022 (with the ".NET desktop development" workload installed).

### Steps

1.  **Open the Solution:**
    *   Navigate to this directory (`VoiceInk.Windows`).
    *   Double-click the `VoiceInk.Windows.sln` file to open the project in Visual Studio.

2.  **Run the Application:**
    *   Once the project is loaded, Visual Studio will automatically restore the required NuGet packages (`NAudio`, `Whisper.net`, etc.).
    *   Press **F5** or click the "Start" button in the toolbar to compile and run the application.

### First-Time Run

The first time you perform a transcription, the `Whisper.net` library will automatically download the required AI model file (`ggml-base.en.bin`). This may take a few moments. The file will be saved to the application's output directory (e.g., `bin/Debug/net8.0-windows`), and subsequent transcriptions will be much faster.
