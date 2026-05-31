```markdown
# voice Development Patterns

> Auto-generated skill from repository analysis

## Overview

This skill teaches you how to contribute effectively to the `voice` Swift codebase, which focuses on audio recording, transcription, and related user interface features. You'll learn the project's coding conventions, how to perform multi-module bugfix and refactor passes, and how to execute performance optimization workflows. The guide also covers commit patterns, file organization, and testing approaches.

## Coding Conventions

### File Naming

- **PascalCase** is used for file names.
  - Example: `AudioVisualizerView.swift`, `TranscriptionPipeline.swift`

### Import Style

- **Relative imports** are preferred.
  - Example:
    ```swift
    import Foundation
    import AVFoundation
    ```

### Export Style

- **Named exports** are used for classes, structs, and functions.
  - Example:
    ```swift
    public class AudioVisualizerView: UIView {
        // ...
    }
    ```

### Commit Patterns

- **Conventional commits** are used, with prefixes like `fix` and `perf`.
- Commit messages average 60 characters and are descriptive.
  - Example:
    ```
    fix: handle audio session interruption in CoreAudioRecorder
    perf: optimize waveform rendering in AudioVisualizerView
    ```

## Workflows

### Multi-Module Bugfix and Refactor

**Trigger:** When you need to resolve multiple bugs and code issues found during a comprehensive audit or review.  
**Command:** `/audit-fix`

1. **Identify and list bugs or code smells** across modules.
2. **Apply targeted fixes** to each affected file (e.g., add error handling, refactor logic, improve resource management).
3. **Refactor code** for maintainability and performance where necessary.
4. **Update related files** to ensure consistency (e.g., models, services, views).
5. **Commit all changes** in a single, descriptive commit.

**Example:**
```swift
// Before: Missing error handling
let audioSession = AVAudioSession.sharedInstance()
try audioSession.setCategory(.playAndRecord)

// After: Added error handling
let audioSession = AVAudioSession.sharedInstance()
do {
    try audioSession.setCategory(.playAndRecord)
} catch {
    print("Failed to set audio session category: \(error)")
}
```

### Performance Optimization Pass

**Trigger:** When you want to improve performance and user experience based on profiling, audits, or user feedback.  
**Command:** `/perf-pass`

1. **Profile or audit** the application to identify performance bottlenecks.
2. **Apply optimizations** such as caching, reducing allocations, debouncing, and simplifying logic in relevant files.
3. **Make minor UX improvements** (e.g., error banners, accessibility enhancements) as needed.
4. **Commit all related changes** together with detailed descriptions.

**Example:**
```swift
// Before: Redundant computation in draw(_:)
override func draw(_ rect: CGRect) {
    let waveform = computeWaveform() // Expensive
    // render waveform
}

// After: Caching the waveform
private var cachedWaveform: [Float]?
override func draw(_ rect: CGRect) {
    if cachedWaveform == nil {
        cachedWaveform = computeWaveform()
    }
    // render cachedWaveform
}
```

## Testing Patterns

- **Test files** follow the pattern `*.test.*` (e.g., `AudioVisualizerView.test.swift`).
- **Testing framework** is unknown; check for test files in the repository for more details.
- Tests are likely written in Swift, matching the main codebase.

**Example:**
```swift
import XCTest
@testable import VoiceInk

class AudioVisualizerViewTests: XCTestCase {
    func testWaveformRendering() {
        // Test implementation
    }
}
```

## Commands

| Command      | Purpose                                                               |
|--------------|-----------------------------------------------------------------------|
| /audit-fix   | Run a multi-module bugfix and refactor pass across the codebase       |
| /perf-pass   | Apply a batch of performance optimizations and UX improvements        |
```
