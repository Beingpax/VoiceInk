# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

### Building the Project
```bash
# Build whisper.cpp framework (prerequisite)
cd whisper.cpp
./build-xcframework.sh

# Build VoiceInk in Xcode
# Use Cmd+B or Product > Build
# Use Cmd+R or Product > Run
```

### Testing
```bash
# Run tests in Xcode
# Use Cmd+U or Product > Test
# Tests use Swift Testing framework (@Test)
```

### Debugging & Development
```bash
# Clean build folder
# Use Cmd+Shift+K in Xcode

# Clean build cache
# Use Cmd+Shift+K twice in Xcode
```

## Architecture Overview

### Core Technology Stack
- **SwiftUI** - Primary UI framework with declarative interfaces
- **SwiftData** - Data persistence for transcription history
- **AVFoundation** - Audio recording and processing
- **whisper.cpp** - Core transcription engine (C++ library via XCFramework)
- **AppKit** - macOS-specific functionality

### Key Dependencies
- **Sparkle** (2.7.0) - Auto-update system
- **KeyboardShortcuts** (2.3.0) - Global hotkey management
- **LaunchAtLogin-Modern** - System startup integration
- **Zip** (2.1.2) - Archive utilities

### Application Architecture

**Main App Structure:**
- `VoiceInkApp` - Main app with dependency injection and service initialization
- `WhisperState` - Central state management for transcription
- `MenuBarManager` - Menu bar interface and controls
- `HotkeyManager` - Global keyboard shortcut handling

**Service Layer:**
- `AIService` - AI processing and enhancement
- `TranscriptionService` - Audio-to-text conversion
- `AudioDeviceManager` - Audio input/output management
- `CloudTranscriptionService` - Multiple cloud provider support

**Data Models:**
- `Transcription` - SwiftData model for history
- `TranscriptionModel` - Protocol for transcription providers
- `WhisperModel` - Local model configuration

### Transcription Provider Architecture
The app uses a plugin-like system with the `TranscriptionModel` protocol:
- **Local**: whisper.cpp models (offline, privacy-first)
- **Cloud**: Groq, ElevenLabs, Deepgram, Custom providers
- **Fallback**: Automatic provider switching on failure

### Key Features Architecture

**PowerMode System:**
- App-specific configurations based on active application
- Browser URL detection for contextual settings
- Automatic prompt and model switching

**Audio Processing:**
- VAD (Voice Activity Detection) integration
- Real-time visualization during recording
- Multiple audio device support

**Privacy-First Design:**
- Offline-first with local whisper.cpp models
- Optional cloud services with explicit consent
- No telemetry in offline mode

## Project Structure

### Core Modules
- `VoiceInk/Whisper/` - whisper.cpp integration and state management
- `VoiceInk/Services/` - Business logic and external service integrations
- `VoiceInk/Views/` - SwiftUI interface components
- `VoiceInk/Models/` - Data models and business entities
- `VoiceInk/PowerMode/` - Context-aware configuration system

### Testing
- `VoiceInkTests/` - Unit tests using Swift Testing framework
- `VoiceInkUITests/` - UI automation tests

## Development Notes

### whisper.cpp Integration
The project requires manual integration of whisper.cpp XCFramework:
1. Clone and build whisper.cpp separately
2. Add the built XCFramework to project manually
3. Link in "Frameworks, Libraries, and Embedded Content"

### SwiftData Configuration
- Uses app-specific Application Support directory
- Schema includes `Transcription` model for history
- Automatic cleanup of old audio files

### Menu Bar App Pattern
- Primary interface is menu bar extra
- Optional main window for settings
- Designed for productivity workflows

### Security Considerations
- Non-sandboxed app for system integration
- Required entitlements: audio input, screen capture, Apple Events
- Keychain storage for API credentials

## Common Development Patterns

### State Management
- Use `@StateObject` for service initialization
- Share service instances via dependency injection
- Environment objects for view hierarchy

### Audio Processing
- AVAudioRecorder for capture
- Custom audio device selection
- Real-time processing with whisper.cpp

### UI Patterns
- SwiftUI with AppKit integration for macOS-specific features
- Custom window management for panels
- Notification system for user feedback

### Error Handling
- Service-level error propagation
- User-friendly error messages
- Fallback mechanisms for transcription failures