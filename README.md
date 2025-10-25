<div align="center">
  <img src="VoiceInk/Assets.xcassets/AppIcon.appiconset/256-mac.png" width="180" height="180" />
  <h1>VoiceInk Community</h1>
  <p>macOS voice-to-text without paywalls, trials, or API key juggling</p>

  [![License](https://img.shields.io/badge/License-GPL%20v3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
  ![Platform](https://img.shields.io/badge/platform-macOS%2014.0%2B-brightgreen)
</div>

---

VoiceInk Community is a maintained fork of the original VoiceInk project. It keeps the same fast, privacy-first transcription experience but removes the paywall, bundles offline models, and relaxes the contribution process so anyone can help shape the app.

Highlights of this fork:

- 💸 **Fully unlocked** – no trials, license prompts, or gated features.
- 📦 **Models included** – Whisper (multiple sizes) and Parakeet ship in the app, ready to use offline.
- 🔧 **Hackable by default** – a friendlier contributing policy and cleaner onboarding for builders.

![VoiceInk Mac App](https://github.com/user-attachments/assets/12367379-83e7-48a6-b52c-4488a6a04bba)

## Features

- 🎙️ **Offline transcription** – Whisper, Parakeet, and Apple Speech models are bundled and ready on first launch.
- 🔒 **Privacy first** – audio and transcripts stay local unless you explicitly export them.
- ⚡ **Power Mode** – detect the active app/URL and auto-apply prompts, models, and paste rules.
- 🎯 **Global shortcuts** – flexible hotkeys, push-to-talk, and middle-click control.
- 📝 **Custom vocabulary** – dictionaries, word replacements, and CSV import/export.
- 💬 **Optional enhancements** – local formatting works out of the box; Ollama hooks stay available for power users.

## Get Started

### Download or Build

- **Releases** – check the repository releases tab for notarized builds of the community edition.
- **Homebrew (optional)** – once a tap is available you’ll be able to `brew install --cask voiceink-community`.
- **From source** – follow [BUILDING.md](BUILDING.md) to compile the app with Xcode. Run `./scripts/download-models.sh` beforehand to drop the default Whisper binaries into the bundle if you haven’t downloaded them yet.

## Requirements

- macOS 14.0 or later

## Documentation

- [Building from Source](BUILDING.md) - Detailed instructions for building the project
- [Contributing Guidelines](CONTRIBUTING.md) - How to contribute to VoiceInk
- [Code of Conduct](CODE_OF_CONDUCT.md) - Our community standards

## Contributing

Pull requests are welcome without prior approval. Read the lightweight [CONTRIBUTING.md](CONTRIBUTING.md) for tips, spin up a branch, and open a PR when ready. If you want early feedback, drafts and GitHub Discussions are perfect places to start the conversation.

## License

This project is licensed under the GNU General Public License v3.0 - see the [LICENSE](LICENSE) file for details.

## Support

If you run into trouble:
1. Search existing GitHub issues and discussions.
2. Open a new issue with logs, screenshots, or steps to reproduce.
3. Join the Discord (linked inside the app) for quick questions or pairing sessions.

## Acknowledgments

### Core Technology
- [whisper.cpp](https://github.com/ggerganov/whisper.cpp) - High-performance inference of OpenAI's Whisper model
- [FluidAudio](https://github.com/FluidInference/FluidAudio) - Used for Parakeet model implementation

### Essential Dependencies
- [Sparkle](https://github.com/sparkle-project/Sparkle) - Keeping VoiceInk up to date
- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) - User-customizable keyboard shortcuts
- [LaunchAtLogin](https://github.com/sindresorhus/LaunchAtLogin) - Launch at login functionality
- [MediaRemoteAdapter](https://github.com/ejbills/mediaremote-adapter) - Media playback control during recording
- [Zip](https://github.com/marmelroy/Zip) - File compression and decompression utilities

---

Maintained with ❤️ by the VoiceInk Community
