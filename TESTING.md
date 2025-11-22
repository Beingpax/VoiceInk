# VoiceInk Testing Framework

**Created:** November 5, 2025  
**Status:** Infrastructure Complete, Tests Ready for Execution  
**Coverage Goal:** 85%+ on critical paths

---

## Overview

This document describes the comprehensive testing framework built for VoiceInk to identify and prevent crashes across all critical systems.

## Test Infrastructure Created

### ✅ Phase 1: Foundation (Complete)

#### Test Utilities (`VoiceInkTests/Infrastructure/`)

1. **TestCase+Extensions.swift** - Core testing utilities
   - Memory leak detection (`assertNoLeak`, `assertNoLeakAsync`)
   - Actor isolation verification (`assertMainActor`, `assertCompletesOnMainActor`)
   - Async testing helpers (`waitAsync`, `assertThrowsAsync`)
   - File system helpers (`createTemporaryDirectory`, `assertTemporaryFilesCleared`)
   - State machine validation (`assertValidTransition`)
   - Concurrency testing (`assertConcurrentExecution`, `assertNoRaceCondition`)

2. **ActorTestUtility.swift** - Advanced concurrency testing
   - Actor isolation verification
   - Serialized access testing
   - MainActor execution validation
   - Race condition detection
   - Task cancellation testing
   - Performance measurement
   - Task group error handling

3. **AudioTestHarness.swift** - Audio system testing
   - Simulated audio devices
   - Audio buffer generation (silence, noise, sine wave, speech-like)
   - Test audio file creation
   - Audio level simulation with patterns
   - Format conversion testing
   - Device state simulation
   - Audio metrics (RMS, peak, speech detection)

4. **FileSystemHelper.swift** - File system testing utilities
   - Isolated directory management
   - Test structure creation
   - File existence assertions
   - File handle tracking
   - Disk space simulation
   - Permission testing
   - Directory monitoring
   - Atomic operations
   - Cleanup verification with snapshots

#### Mock Services (`VoiceInkTests/Mocks/`)

1. **MockAudioDevice.swift**
   - Simulated audio devices with configurable properties
   - MockAudioDeviceManager for device lifecycle testing
   - Device connect/disconnect simulation

2. **MockTranscriptionService.swift**
   - Configurable success/failure scenarios
   - Call tracking and verification
   - Delay simulation
   - Mock cloud and local transcription services

3. **MockModelContext.swift**
   - SwiftData testing without persistence
   - Operation tracking (insert, delete, save, fetch)
   - Error injection
   - In-memory container helper

### ✅ Phase 2: Unit Tests Started

#### Audio System Tests (`VoiceInkTests/AudioSystem/`)

1. **RecorderTests.swift** (15 tests) - CREATED
   - ✅ Basic lifecycle (start/stop without crash)
   - ✅ Multiple start/stop cycles
   - ✅ Stop without start (no crash)
   - ✅ Stop before start completes (race condition)
   - ✅ Memory leak detection after multiple sessions
   - ✅ Timer cleanup in deinit
   - ✅ Audio meter updates without leak
   - ✅ Device change during recording
   - ✅ Concurrent stop calls
   - ✅ Rapid start attempts
   - ✅ File cleanup on failed recording
   - ✅ No audio detected warning
   - ✅ Session reset verification
   - ✅ Recording duration updates
   - ✅ Delegate callbacks on correct thread
   - ✅ Observer cleanup in deinit

---

## Critical Crash Vectors Identified

Based on deep codebase analysis, these are the high-risk areas:

### 1. Memory Management (HIGH SEVERITY)
- **45+ `[weak self]` closures** - Potential dangling references
- **10+ deinit implementations** - Task cancellation verification needed
- **Timer leaks** in: AudioPlayerService, Recorder, TTSViewModel, AudioLevelMonitor
- **NotificationCenter observers** - 8+ files requiring cleanup
- **AVAudioEngine lifecycle** - Improper stop() = crashes

**Tests Created:** Recorder memory leak tests, timer cleanup verification

### 2. Actor Isolation Violations (HIGH SEVERITY)
- **WhisperContext** is an actor - concurrent access crashes
- **@MainActor classes with nonisolated deinit** using Task wrapping
- **AudioLevelMonitor** has nonisolated deinit with @MainActor work
- **Async callbacks** from AVAudioRecorderDelegate need proper dispatch

**Tests Created:** Actor test utilities, concurrency stress tests ready

### 3. Audio Pipeline Race Conditions (CRITICAL)
- **Device switching during recording** (handleDeviceChange in Recorder)
- **Multiple recording attempts** without locking
- **AVAudioEngine start/stop** without synchronization
- **Audio tap cleanup** while processing
- **Recorder.isReconfiguring flag** not thread-safe

**Tests Created:** Device change tests, concurrent access tests

### 4. File System Hazards (MEDIUM-HIGH)
- **Temporary file cleanup** in defer blocks
- **Concurrent access** to recordingsDirectory
- **Model file downloads** with progress tracking
- **No file handle limit checking**
- **WhisperContext model loading** - file lock contention

**Tests Created:** File cleanup verification, directory isolation

### 5. Network & API Integration (MEDIUM)
- **CloudTranscriptionService** - 7 providers with different error modes
- **KeychainManager** - OSStatus errors
- **SecureURLSession** - cleanup verification needed
- **No API rate limiting** - quota exhaustion

**Tests Created:** Mock network services ready

### 6. SwiftData Threading Issues (HIGH)
- **ModelContext** access from background threads
- **Transcription inserts** during cleanup
- **TranscriptionAutoCleanupService** - timer + context interaction
- **Container initialization** fallback logic

**Tests Created:** MockModelContext for isolated testing

### 7. State Machine Corruption (CRITICAL)
- **RecordingState transitions** without locks
- **TranscriptionStage** concurrent mutations
- **PowerModeSessionManager** - flag without sync
- **shouldCancelRecording** checked from multiple tasks

**Tests Created:** State transition validation helpers

---

## Tests Still To Implement

### Phase 2: Unit Tests (Remaining ~113 tests)

#### AudioDeviceManager (12 tests)
- Device enumeration with no devices
- Device UID persistence
- Fallback to system default
- Prioritized device selection
- Device change notifications
- getCurrentDevice thread safety
- isRecordingActive flag consistency
- Property observer cleanup
- Audio device property errors
- Invalid device ID handling
- Device availability checking
- Concurrent loadAvailableDevices

#### AudioLevelMonitor (13 tests)
- Start/stop lifecycle
- Nonisolated deinit Task execution
- Monitoring while already active
- Stop while not monitoring
- Device setup failures
- Invalid audio format handling
- Buffer processing thread safety
- Timer cleanup verification
- Audio tap removal
- Engine cleanup order
- Concurrent start/stop
- Level smoothing accuracy
- RMS to dB conversion edge cases

#### WhisperState (20 tests)
- toggleRecord state machine
- shouldCancelRecording races
- Model loading cancellation
- transcribeAudio with invalid URL
- Concurrent transcription attempts
- cleanupModelResources verification
- dismissMiniRecorder idempotency
- PowerMode session integration
- Enhancement service handling
- Transcription status updates
- File cleanup on cancellation
- checkCancellationAndCleanup
- RecordingState transitions
- Model warmup coordinator
- Parakeet model loading
- Prompt detection integration
- Word replacement application
- Text formatting toggle
- Audio file URL conversion
- Transcription metadata accuracy

#### WhisperContext (10 tests)
- Actor isolation enforcement
- Model initialization failures
- fullTranscribe sample buffer safety
- VAD model path setting
- Language selection persistence
- Prompt C string lifecycle
- releaseResources cleanup
- Concurrent transcription serialization
- deinit whisper_free called
- Flash attention Metal availability

#### TTSViewModel (28 tests)
- Generate speech lifecycle
- Batch processing cancellation
- Preview voice concurrent calls
- Audio player state consistency
- Character limit enforcement
- Provider switching mid-generation
- Translation result caching
- Article summarization management
- Style control persistence
- Snippet insertion modes
- Transcription recording timer
- Ephemeral file URL tracking
- deinit task cancellation (5 tasks)
- Notification authorization
- Managed provisioning lifecycle
- ElevenLabs voice fetching
- Pronunciation rules
- Loop playback
- Format switching
- Cost estimation
- Batch delimiter parsing
- Transcription stage transitions
- Publisher sink cleanup
- Audio player callbacks
- Volume/playback rate clamping
- URL content loading errors
- Appearance preference persistence
- Character overflow highlighting

#### Service Layer (25 tests)
- PowerModeSessionManager (8 tests)
- KeychainManager (8 tests)
- ScreenCaptureService (5 tests)
- VoiceActivityDetector (4 tests)

### Phase 3: Integration Tests (~23 tests)
- End-to-end workflows (15 tests)
- Error recovery scenarios (8 tests)

### Phase 4: Stress & Leak Tests (~40 tests)
- Memory leak detection (20 scenarios)
- Concurrency stress (12 scenarios)
- State machine fuzzing (8 scenarios)

### Phase 5: UI Tests (~15 tests)
- Onboarding flow
- Settings interactions
- Model management
- Mini recorder UI
- TTS workspace
- Dictionary CRUD
- Power Mode configuration
- And more...

---

## How to Run Tests

### Prerequisites
- macOS 14.0+ (Sonoma)
- Xcode 16.0+
- Development certificate for signing (or disable signing for tests)

### Command Line

```bash
# Build tests
xcodebuild build-for-testing \
  -project VoiceInk.xcodeproj \
  -scheme VoiceInk \
  -destination 'platform=macOS,arch=arm64'

# Run all tests
xcodebuild test \
  -project VoiceInk.xcodeproj \
  -scheme VoiceInk \
  -destination 'platform=macOS,arch=arm64'

# Run specific test class
xcodebuild test \
  -project VoiceInk.xcodeproj \
  -scheme VoiceInk \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:VoiceInkTests/RecorderTests

# Run with Thread Sanitizer (detect data races)
xcodebuild test \
  -project VoiceInk.xcodeproj \
  -scheme VoiceInk \
  -destination 'platform=macOS,arch=arm64' \
  -enableThreadSanitizer YES
```

### Xcode IDE

1. Open `VoiceInk.xcodeproj`
2. Select the Test navigator (⌘6)
3. Run individual tests or entire suites
4. View test results and coverage

### Enabling Sanitizers

For memory and concurrency issue detection:

1. **Product** → **Scheme** → **Edit Scheme**
2. Select **Test** action
3. Go to **Diagnostics** tab
4. Enable:
   - ✅ Thread Sanitizer (detect data races)
   - ✅ Address Sanitizer (detect memory issues)
   - ✅ Undefined Behavior Sanitizer
   - ✅ Malloc Scribble (detect use-after-free)

---

## Test Organization

```
VoiceInkTests/
├── Infrastructure/              # Test utilities and helpers
│   ├── TestCase+Extensions.swift
│   ├── ActorTestUtility.swift
│   ├── AudioTestHarness.swift
│   └── FileSystemHelper.swift
├── Mocks/                       # Mock services for isolation
│   ├── MockAudioDevice.swift
│   ├── MockTranscriptionService.swift
│   └── MockModelContext.swift
├── AudioSystem/                 # Audio pipeline tests
│   ├── RecorderTests.swift      ✅ CREATED (15 tests)
│   ├── AudioDeviceManagerTests.swift (TODO)
│   └── AudioLevelMonitorTests.swift (TODO)
├── Transcription/               # Transcription system tests (TODO)
│   ├── WhisperStateTests.swift
│   ├── WhisperContextTests.swift
│   └── CloudTranscriptionTests.swift
├── TTS/                         # Text-to-Speech tests (TODO)
│   ├── TTSViewModelTests.swift
│   └── TTSProviderTests.swift
├── Services/                    # Service layer tests (TODO)
│   ├── PowerModeTests.swift
│   ├── KeychainTests.swift
│   └── ScreenCaptureTests.swift
├── Integration/                 # End-to-end tests (TODO)
│   └── WorkflowTests.swift
├── Stress/                      # Stress and leak tests (TODO)
│   ├── MemoryLeakTests.swift
│   └── ConcurrencyStressTests.swift
└── UI/                          # UI tests (TODO)
    └── OnboardingTests.swift
```

---

## Coverage Goals

| Component | Target Coverage | Priority |
|-----------|----------------|----------|
| Recorder | 95% | P0 - Critical |
| WhisperState | 90% | P0 - Critical |
| AudioDeviceManager | 85% | P0 - Critical |
| TTSViewModel | 85% | P1 - High |
| TranscriptionService | 80% | P1 - High |
| PowerModeSessionManager | 80% | P1 - High |
| KeychainManager | 95% | P0 - Security |
| AudioLevelMonitor | 85% | P1 - High |
| UI Components | 60% | P2 - Medium |

---

## Known Limitations

1. **Signing Required**: Tests require valid development certificates or signing disabled
2. **Microphone Access**: Some audio tests may need microphone permissions
3. **Model Files**: WhisperContext tests need actual model files (or mocked)
4. **Network Tests**: Cloud transcription tests need network access or mocking
5. **UI Tests**: Require accessibility permissions

---

## Next Steps

1. **Complete Audio System Tests** (27 remaining tests)
   - AudioDeviceManager (12 tests)
   - AudioLevelMonitor (13 tests)
   - SwiftData integration (2 tests)

2. **Implement Transcription Tests** (35 tests)
   - WhisperState (20 tests)
   - WhisperContext (10 tests)
   - CloudTranscriptionService (5 tests)

3. **Build TTS Test Suite** (28 tests)
   - TTSViewModel comprehensive coverage

4. **Add Integration Tests** (23 tests)
   - Critical workflow testing
   - Error recovery scenarios

5. **Stress Testing** (40 tests)
   - Memory leak detection
   - Concurrency stress
   - State machine fuzzing

6. **Run Full Suite**
   - Collect coverage metrics
   - Identify crashes
   - Fix issues with regression tests

7. **Document Findings**
   - Create CRASH_FIXES.md
   - Update CI/CD integration guide

---

## Success Metrics

✅ **Infrastructure Complete** - 4 test utilities, 3 mock services  
⏳ **15/200+ Unit Tests** - RecorderTests complete  
⏳ **0/23 Integration Tests**  
⏳ **0/40 Stress Tests**  
⏳ **0/15 UI Tests**  

### When Complete:
- ✅ 200+ tests covering all critical paths
- ✅ 85%+ code coverage on high-risk areas
- ✅ Zero crashes in core recording/transcription flows
- ✅ All memory leaks identified and fixed
- ✅ Concurrency violations resolved
- ✅ State machines validated
- ✅ CI/CD integration

---

## Contributing

When adding new tests:

1. Use existing test utilities in `Infrastructure/`
2. Follow naming conventions: `test[WhatIsBeingTested]`
3. Always clean up resources in `tearDown`
4. Track memory leaks with `assertNoLeak`
5. Verify thread safety with `assertMainActor`
6. Document crash fixes in CRASH_FIXES.md

---

**For questions or issues with testing, see AGENTS.md for detailed coding guidelines.**
