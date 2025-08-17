# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

### Build & Run
- Open the project in Xcode: `open VoiceInk.xcodeproj`
- Build: `⌘+B` in Xcode or `xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk build`
- Run: `⌘+R` in Xcode or build and launch the app
- Clean: `⌘+Shift+K` in Xcode

### Testing
- Run tests: `⌘+U` in Xcode or `xcodebuild test -project VoiceInk.xcodeproj -scheme VoiceInk`

### Dependencies
- Build whisper.cpp framework: `cd whisper.cpp && ./build-xcframework.sh`
- The whisper.xcframework must be manually added to the Xcode project
- **Important**: Fix package dependencies if needed (see BUILD_TROUBLESHOOTING.md)
- Clean derived data if builds fail: `rm -rf ~/Library/Developer/Xcode/DerivedData/VoiceInk-*`

## Architecture

### Core Components
- **VoiceInkApp.swift**: Main app entry point with SwiftData container, dependency injection for all services, and environment setup
- **WhisperState**: Core state management for recording, transcription, and model loading. Handles the entire audio processing pipeline
- **ContentView**: Main UI with navigation split view and ViewType enum for different app sections

### Service Layer Architecture
- **TranscriptionService**: Protocol with multiple implementations (LocalTranscriptionService, CloudTranscriptionService, ParakeetTranscriptionService)
- **AIEnhancementService**: Handles AI-powered text enhancement with screen context awareness
- **ScreenCaptureService**: Screen capture functionality (currently disabled due to deprecated API)
- **ActiveWindowService**: Power Mode functionality that detects active apps and applies configurations
- **AudioDeviceManager**: Manages audio input devices and configurations
- **WordReplacementService**: Personal dictionary with custom word replacements

### Key Directories
- `VoiceInk/`: Main app source code
- `VoiceInk/Models/`: Data models and prompts
- `VoiceInk/Services/`: Business logic services
- `VoiceInk/Views/`: SwiftUI views organized by feature
- `VoiceInk/Whisper/`: Local transcription and model management
- `VoiceInk/PowerMode/`: Context-aware app detection and configuration
- `VoiceInk/Resources/`: Audio files, scripts, and bundled ML models

### Data Flow
1. Audio recording via Recorder class to permanent file URLs
2. Transcription through provider-specific services (local, cloud, native)
3. Optional AI enhancement with screen context
4. Text processing (word replacements, prompt detection)
5. Output via CursorPaster with clipboard preservation
6. Storage in SwiftData (Transcription model)

### Key Features
- **Power Mode**: Automatic app detection and configuration switching
- **Multiple Transcription Providers**: Local whisper.cpp, cloud APIs, Parakeet ASR
- **AI Enhancement**: Context-aware text improvement (screen capture currently disabled)
- **Personal Dictionary**: Custom word replacements and terminology
- **Hotkey Management**: Global shortcuts for recording
- **Menu Bar Interface**: Always-accessible UI

### External Dependencies
- **whisper.cpp**: Local AI transcription (requires manual framework build)
- **Sparkle**: Auto-updates
- **KeyboardShortcuts**: Global hotkey management
- **LaunchAtLogin**: Startup functionality
- **SwiftData**: Local data persistence

## Known Issues & Fixes

### Removed Components
- **NativeAppleTranscriptionService**: Removed entirely due to usage of non-existent macOS 26 APIs
- **Screen Capture**: Disabled due to deprecated `CGWindowListCreateImage` API (needs ScreenCaptureKit migration)

### Build Fixes Applied
- Fixed malformed Zip package URL in project.pbxproj (`?tab=readme-ov-file` suffix removed)
- Updated Package.resolved to match corrected URL
- Set deployment target to macOS 15.0 for compatibility
- Commented out deprecated screen capture APIs

### Bundle Configuration
- Bundle identifier: `com.rohatcan.VoiceInk`
- Deployment target: macOS 15.0
- Code signing: Apple Development certificate required