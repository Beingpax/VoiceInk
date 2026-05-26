<div align="center">
  <img src="VoiceInk/Assets.xcassets/AppIcon.appiconset/256-mac.png" width="180" height="180" />
  <h1>VoiceInk</h1>
  <p>Voice to text app for macOS to transcribe what you say to text almost instantly</p>

  [![License](https://img.shields.io/badge/License-GPL%20v3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
  ![Platform](https://img.shields.io/badge/platform-macOS%2014.0%2B-brightgreen)
  [![GitHub release (latest by date)](https://img.shields.io/github/v/release/Beingpax/VoiceInk)](https://github.com/Beingpax/VoiceInk/releases)
  ![GitHub all releases](https://img.shields.io/github/downloads/Beingpax/VoiceInk/total)
  ![GitHub stars](https://img.shields.io/github/stars/Beingpax/VoiceInk?style=social)
  <p>
    <a href="https://tryvoiceink.com">Website</a> •
    <a href="https://www.youtube.com/@tryvoiceink">YouTube</a>
  </p>

  <a href="https://tryvoiceink.com">
    <img src="https://img.shields.io/badge/Download%20Now-Latest%20Version-blue?style=for-the-badge&logo=apple" alt="Download VoiceInk" width="250"/>
  </a>
</div>

---

VoiceInk is a native macOS application that transcribes what you say to text almost instantly. You can find all the information and download the app from [here](https://tryvoiceink.com). 

![VoiceInk Mac App](https://github.com/user-attachments/assets/12367379-83e7-48a6-b52c-4488a6a04bba)

After dedicating the past 5 months to developing this app, I've decided to open source it for the greater good. 

My goal is to make it **the most efficient and privacy-focused voice-to-text solution for macOS** that is a joy to use. While the source code is now open for experienced developers to build and contribute, purchasing a license helps support continued development and gives you access to automatic updates, priority support, and upcoming features.

## Features

- 🎙️ **Accurate Transcription**: Local AI models that transcribe your voice to text with 99% accuracy, almost instantly
- 🔒 **Privacy First**: 100% offline processing ensures your data never leaves your device
- ⚡ **Modes**: Intelligent app detection automatically applies your perfect pre-configured settings based on the app/ URL you're on
- 🧠 **Context Aware**: Smart AI that understands your screen content and adapts to the context
- 🎯 **Global Shortcuts**: Configurable keyboard shortcuts for quick recording and push-to-talk functionality
- 📝 **Personal Dictionary**: Train the AI to understand your unique terminology with custom words, industry terms, and smart text replacements
- 🔄 **Smart Modes**: Instantly switch between AI-powered modes optimized for different writing styles and contexts
- 🤖 **AI Assistant**: Built-in voice assistant mode for a quick chatGPT like conversational assistant

## Get Started

### Download
Get the latest version with a free trial from [tryvoiceink.com](https://tryvoiceink.com). Your purchase helps me work on VoiceInk full-time and continuously improve it with new features and updates.

#### Homebrew
Alternatively, you can install VoiceInk via `brew`:

```shell
brew install --cask voiceink
```

### Build from Source
As an open-source project, you can build VoiceInk yourself by following the instructions in [BUILDING.md](BUILDING.md). However, the compiled version includes additional benefits like automatic updates, priority support via Discord and email, and helps fund ongoing development.

## Requirements

- macOS 14.4 or later

## Documentation

- [Building from Source](BUILDING.md) - Detailed instructions for building the project
- [Contributing Guidelines](CONTRIBUTING.md) - How to contribute to VoiceInk
- [Code of Conduct](CODE_OF_CONDUCT.md) - Our community standards

## Contributing

This project is **not accepting pull requests** at this time. You're welcome to fork and modify VoiceInk for your own use.

You can still contribute by:
- Reporting bugs via [issues](https://github.com/Beingpax/VoiceInk/issues)
- Suggesting features or enhancements
- Improving documentation via issues

For more details, see our [Contributing Guidelines](CONTRIBUTING.md). For build instructions, see our [Building Guide](BUILDING.md).

## License

This project is licensed under the GNU General Public License v3.0 - see the [LICENSE](LICENSE) file for details.

## Support

If you encounter any issues or have questions, please:
1. Check the existing issues in the GitHub repository
2. Create a new issue if your problem isn't already reported
3. Provide as much detail as possible about your environment and the problem

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
- [SelectedTextKit](https://github.com/tisfeng/SelectedTextKit) - A modern macOS library for getting selected text
- [Swift Atomics](https://github.com/apple/swift-atomics) - Low-level atomic operations for thread-safe concurrent programming


---

Made with ❤️ by Pax
