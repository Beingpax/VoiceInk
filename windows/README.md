# VoiceInk for Windows (Rust)

A native Windows port of VoiceInk written in Rust on top of Microsoft's
[`windows`](https://crates.io/crates/windows) crate. You press a shortcut, speak,
and the transcript (optionally cleaned up by an LLM) is pasted wherever your
cursor is. It runs from the notification area, like the macOS menu-bar app.

## Features

| macOS feature | Windows implementation |
|---|---|
| Global shortcut: toggle, push-to-talk, hybrid, modifier-only keys (Right ⌘) | `WH_KEYBOARD_LL` / `WH_MOUSE_LL` hooks: `RightCtrl`, `F9`, `Ctrl+Shift+Space`, `Mouse4`, … |
| CoreAudio recorder (16 kHz mono) | WASAPI shared-mode capture; any mix format is downmixed and resampled to 16 kHz |
| Cloud transcription | OpenAI (default, `gpt-4o-transcribe`), Groq, Deepgram (Nova-3, keyterms), ElevenLabs Scribe, Mistral Voxtral, any OpenAI-compatible endpoint (e.g. a local `whisper.cpp` server) |
| Local whisper.cpp | Optional `local-whisper` build feature (`whisper-rs`) |
| Output filter (`[MUSIC]`, `(laughs)`, tag blocks, filler words) | Ported 1:1 (`text::filter`) |
| Paragraph formatter, word counter | Ported (`text::formatter`, `text::words`) |
| Dictionary: word replacements, custom vocabulary | Ported with the same boundary rules, including CJK/Thai |
| AI enhancement with the VoiceInk system prompt and built-in prompts (Default, Chat, Email, Rewrite, Assistant) | Prompts copied verbatim. Providers: OpenAI, Anthropic, Gemini, Groq, Cerebras, Mistral, OpenRouter, Ollama, custom. Same retry, backoff and rate limit |
| Context: clipboard, selected text, current window | Clipboard text, selection (via Ctrl+C with clipboard restore), window title and process name |
| Modes (per-app settings, trigger words) | Match by process name (`slack.exe`) or window title (`Gmail`); spoken trigger words |
| Paste with clipboard restore, "Finish & Send" | Clipboard + `SendInput` Ctrl+V (or Shift+Insert, or simulated typing). The text is kept out of Win+V history, the previous clipboard (all formats) is restored, and Enter, Shift+Enter or Ctrl+Enter is sent afterwards if configured |
| Custom command output | Runs a command with the text on stdin and in `%VOICEINK_TRANSCRIPT%` |
| Mini recorder panel | Non-activating, always-on-top pill with a live level meter (click to stop) |
| Start/stop sounds, mute system audio while recording | `PlaySoundW` using the original sounds; `IAudioEndpointVolume` |
| Keychain | DPAPI-encrypted `keys.json` (current Windows user only) |
| History | `history.jsonl`, CSV export, "Paste last transcription" shortcut |
| — (new, inspired by Wispr Flow) | **Command Mode**: select text, press `Ctrl+Shift+Space` and say what to do with it ("make this more formal", "translate to German"). The AI result replaces the selection; with nothing selected, it writes new text at the cursor |
| — (new) | **Snippets**: say a trigger phrase ("my calendar link") to insert saved text, with `{date}`, `{time}` and `{datetime}` placeholders |
| Dashboard & Settings | Native window: stats (words, time saved, WPM, streak), a 14-day chart, top apps and recent transcriptions, plus settings pages for General, Transcription, AI Enhancement, Prompts (editor), Dictionary, Output and History |
| Launch at login | `HKCU\…\Run` |

Not ported (they depend on Apple frameworks or macOS-only infrastructure):
Apple Speech, FluidAudio/Parakeet, the VoiceInk Refine XPC model, realtime
streaming providers, screen OCR context and licensing/updates (Sparkle).
Modes are edited in `config.json`; everything else is in the Settings window.

## Install and run

1. Download `voiceink.exe` from the **Windows (Rust)** GitHub Actions run, or build it yourself (see below).
2. Run it. A blue microphone icon appears in the notification area.
3. Click it to open **Dashboard & Settings**, go to **Transcription**, paste your OpenAI key and click **Save**. OpenAI is the default for both transcription and AI enhancement, so one key covers both. Right-click the icon for the quick menu.
4. Click into any text field and tap **Right Ctrl**, speak, then tap **Right Ctrl** again. You can also hold Right Ctrl while you talk.
   **Esc** cancels. **Alt+Shift+V** pastes the last transcription again.
5. **Command Mode:** select some text, tap **Ctrl+Shift+Space**, say an instruction such as "make this shorter", then tap it again. The selection is replaced with the result.

The tray icon is blue when idle, red while recording and amber while processing.

## Build

Requirements: Rust 1.80+ (stable) and the MSVC toolchain (Visual Studio Build Tools).

```powershell
cd windows
cargo build --release          # target\release\voiceink.exe
cargo test                     # tests for the platform-independent core
```

Offline transcription with whisper.cpp needs CMake and a C++ compiler:

```powershell
cargo build --release --features local-whisper
```

Download a model, e.g. `ggml-base.en.bin` from
<https://huggingface.co/ggerganov/whisper.cpp>, into `%APPDATA%\VoiceInk\models`.
Then select **Local (whisper.cpp)** in the tray menu and set
`transcription.model` to the file name.

Cross-compiling from Linux works with MinGW
(`rustup target add x86_64-pc-windows-gnu`, `apt install gcc-mingw-w64-x86-64`,
then `cargo build --release --target x86_64-pc-windows-gnu`).

## Command line

The same executable has CLI subcommands. In release builds it re-attaches to the parent console.

```text
voiceink                          start the tray app
voiceink dashboard                open the dashboard (starts the app if needed)
voiceink settings                 open the settings
voiceink set-key openai sk-...     store an API key (DPAPI-encrypted)
voiceink keys                     list providers with stored keys
voiceink transcribe memo.wav      run the full pipeline on a WAV file
voiceink devices                  list microphones
voiceink history 20               recent transcriptions
voiceink export-history out.csv
voiceink config-path
```

API keys can also come from environment variables, either `VOICEINK_OPENAI_API_KEY` or `OPENAI_API_KEY`.

## Configuration

Everything lives in `%APPDATA%\VoiceInk\`:

| File | Contents |
|---|---|
| `config.json` | All settings (created on first run). Edits are picked up before the next recording, or via **Reload settings** |
| `keys.json` | DPAPI-encrypted API keys |
| `history.jsonl` | Transcription history |
| `voiceink.log` | Log file |

Example `config.json` excerpt:

```json
{
  "hotkeys": { "record": "RightCtrl", "mode": "hybrid", "hybrid_threshold_ms": 500,
               "cancel": "Escape", "paste_last": "Alt+Shift+V" },
  "transcription": { "provider": "openai", "model": null, "language": "auto",
                     "custom_endpoint": "http://127.0.0.1:8080/v1/audio/transcriptions" },
  "enhancement": { "enabled": true, "provider": "openai", "model": null,
                   "prompt_id": "00000000-0000-0000-0000-000000000001",
                   "use_clipboard_context": false, "use_window_context": true },
  "output": { "method": "ctrl_v", "restore_clipboard": true, "send_key": "none" },
  "vocabulary": ["VoiceInk", "Kubernetes"],
  "replacements": [{ "original": "voice ink, voice inc", "replacement": "VoiceInk" }],
  "modes": [
    { "name": "Email", "window_title_contains": ["Gmail", "Outlook"],
      "trigger_words": ["email"], "enhancement_enabled": true,
      "prompt_id": "00000000-0000-0000-0000-000000000003" },
    { "name": "Chat", "process_names": ["slack.exe", "discord.exe", "ms-teams.exe"],
      "prompt_id": "00000000-0000-0000-0000-000000000002", "send_key": "enter" }
  ]
}
```

Command Mode and snippets:

```json
{
  "command": { "enabled": true, "hotkey": "Ctrl+Shift+Space", "provider": null, "model": null },
  "snippets": [
    { "trigger": "my calendar link", "text": "https://cal.com/yourname" },
    { "trigger": "my signature", "text": "Best regards,\nAlex" }
  ]
}
```

- **Command Mode** uses the AI Enhancement provider unless `command.provider` is set, and works even when AI enhancement of normal dictation is off. If the request fails, nothing is pasted, so your selection is never overwritten.
- **Snippets:** if the whole dictation is a trigger, the snippet is inserted as-is and AI is skipped. A trigger inside a longer dictation is expanded after AI clean-up, so the saved text is never rewritten.

Hotkey modes:
- `hybrid` (default): a short tap toggles recording, and holding the key longer than `hybrid_threshold_ms` works as push-to-talk.
- `toggle`: each press starts or stops recording.
- `push_to_talk`: recording runs while the key is held.

A modifier-only shortcut (such as `RightCtrl`) never blocks other shortcuts. If you press another key while holding it (for example RightCtrl+C), the recording it started is discarded.

## Architecture

The crate is a portable core plus a Win32 layer. Dependencies point inwards:
the pipeline knows providers only through traits, and nothing outside
`platform/` touches Windows APIs, so the core is unit tested on any OS.

```
src/
├── main.rs, cli.rs       entry point; CLI parsing (pure) and execution
├── context.rs            composition root: AppContext { paths, secrets, history, services }
├── paths.rs              data directory layout (%APPDATA%\VoiceInk, or VOICEINK_HOME)
├── config/               typed settings, provider catalog, SettingChange (tray menu edits)
├── settings_page.rs      the pages of the settings window (shared by CLI and UI)
├── input/                hotkey parsing, press/release state machine, RecordingPolicy
├── pipeline/             transcribe → filter → format → replace → snippets → enhance; Command Mode
├── transcription/        Transcriber trait + OpenAI-compatible, Deepgram, ElevenLabs, local whisper.cpp
├── enhancement/          ChatModel trait + OpenAI-compatible, Anthropic; rate limiting and retries
├── credentials.rs        SecretStore trait; DPAPI key file, env-var override, in-memory store
├── history.rs            HistoryStore (JSON Lines), CSV export
├── text/, audio/, prompts.rs, modes.rs, stats.rs, http.rs
└── platform/             Win32 via the `windows` crate (Windows only)
    ├── app/              tray app: window + message loop, controller (state machine),
    │                     menu (MenuAction registry), delivery, events, config_file
    ├── settings/         Dashboard & Settings: one type per page behind the Page trait,
    │                     typed control wrappers, stats panel
    ├── capture.rs        WASAPI microphone capture
    ├── hotkey.rs         low-level keyboard/mouse hooks feeding input::ShortcutSet
    ├── paste.rs, clipboard.rs, foreground.rs   SendInput, clipboard, focus
    ├── overlay.rs, tray.rs, icon.rs, gdi.rs    recorder pill, tray icon/menus, GDI RAII helpers
    └── com.rs, error.rs, sound.rs, volume.rs, autostart.rs, actions.rs
```

UI work happens on the main thread. Recording, transcription and pasting run
on worker threads, which report back through a channel (`app::events`) and a
`PostMessageW` wake-up. Coding standards are in
[CONTRIBUTING-windows.md](CONTRIBUTING-windows.md).

## Notes

- Windows won't let a normal process send keystrokes into apps running as administrator. To dictate into those, run VoiceInk as administrator as well.
- If an app ignores Ctrl+V (some terminals), choose **Options › Insert text with › Shift+Insert** or **Simulated typing**.
- Microphone access has to be allowed under *Settings › Privacy & security › Microphone › Let desktop apps access your microphone*.
