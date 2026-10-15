# VoiceInk for Windows (C# / .NET 10 / WinUI 3)

A Windows-only port of the Rust variant in [`../windows`](../windows), written in C# on the latest .NET and designed for
Windows 11 with **WinUI 3** (Windows App SDK, Mica, Fluent controls). Offline transcription uses
[**Whisper.net**](https://github.com/sandrohanea/whisper.net) (whisper.cpp, Vulkan GPU acceleration when available).

You press a shortcut, speak, and the transcript (optionally cleaned up by an LLM) is pasted wherever your cursor is.
It lives in the notification area; the dashboard and settings open from the tray icon.

## Features

Everything the Rust version does, with the same `config.json` format:

- Global shortcut with toggle, push-to-talk and hybrid mode, modifier-only keys (`RightCtrl`), mouse buttons.
- WASAPI capture (any mix format → 16 kHz mono), start/stop sounds, mute system audio while recording.
- Transcription: OpenAI, Groq, Deepgram, ElevenLabs, Mistral, any OpenAI-compatible endpoint, **and local Whisper
  models** with an in-app model downloader.
- AI enhancement with the VoiceInk prompts (OpenAI, Anthropic, Gemini, Groq, Cerebras, Mistral, OpenRouter, Ollama, custom).
- **Command Mode** (`Ctrl+Shift+Space`): select text, say what to do with it.
- Snippets, dictionary replacements, custom vocabulary, filler-word filter, paragraph formatting.
- Modes per app / window title / spoken trigger word (edited in the UI), custom command output, "Finish & Send".
- Paste with full clipboard restore (kept out of Win+V history), Shift+Insert and simulated typing.
- **WinUI dashboard**: words, time saved, WPM, streak, 14-day chart, top apps, recent transcriptions; settings pages for
  everything above; Mica backdrop, light/dark theme, acrylic non-activating recorder pill with live level meter.
- DPAPI-encrypted API keys, history (`history.jsonl`, CSV export), launch at login, single instance, CLI.

## Build

Requirements: Windows 10 1809+ / Windows 11, [.NET 10 SDK](https://dotnet.microsoft.com/download).

```powershell
cd windows-dotnet
dotnet test tests/VoiceInk.Core.Tests
dotnet publish src/VoiceInk.App -c Release -r win-x64 -p:Platform=x64 --self-contained -o artifacts/VoiceInk
artifacts\VoiceInk\VoiceInk.exe
```

The WinUI app is self-contained (no Windows App SDK runtime install needed). The portable core builds and tests on any OS.

## Command line

```text
VoiceInk.exe                          start the tray app
VoiceInk.exe dashboard | settings     open the window (starts the app if needed)
VoiceInk.exe set-key openai sk-...    store an API key (DPAPI)
VoiceInk.exe transcribe memo.wav      run the full pipeline on a WAV file
VoiceInk.exe devices | keys | history 20 | export-history out.csv | config-path
```

## Architecture

Dependencies point inwards; the recording logic knows nothing about Windows or WinUI.

```
src/
├── VoiceInk.Core        net10.0, portable. Config, prompts, text processing, audio math, providers, pipeline,
│   └── Dictation/       DictationController (state machine) + the interfaces it needs (IAudioCapture, IForeground,
│                        ITextOutput, IHotkeyService, INotifier, ...) and HotkeyEngine (pure shortcut logic)
├── VoiceInk.Platform    net10.0-windows. Implements those interfaces: low-level hooks, SendInput, clipboard,
│                        NAudio/WASAPI, PlaySound, DPAPI, tray icon, foreground tracking
└── VoiceInk.App         WinUI 3. Composition root (AppServices), tray menu, recorder pill, main window, pages
tests/VoiceInk.Core.Tests
```

## Notes

- Windows won't let a normal process send keystrokes into apps running as administrator; run VoiceInk elevated to dictate there.
- If an app ignores Ctrl+V, choose **Output & Audio › Insert text with › Shift+Insert / Simulated typing**.
- Allow microphone access under *Settings › Privacy & security › Microphone › Let desktop apps access your microphone*.

## NativeAOT portable package (x64)

On Windows, install the .NET 10 SDK and Visual Studio 2022 Desktop development with C++ workload (MSVC x64/x86 tools and Windows SDK). From `windows-dotnet`, run:

```powershell
./scripts/package-nativeaot.ps1
```

The script publishes with `Properties/PublishProfiles/NativeAOT.pubxml`, creates a ZIP in `artifacts/`, copies it to `../release/windows/` (creating the folder if needed), and prints its SHA-256 hash. Extract the entire archive and run `VoiceInk.exe`; keep the Windows App SDK and Whisper native libraries alongside the executable. AOT uses a separate `bin/aot` app build directory. The regular publish command remains available.

NativeAOT compilation requires the C++ linker; a successful managed build alone does not produce a NativeAOT executable.
