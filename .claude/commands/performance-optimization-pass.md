---
name: performance-optimization-pass
description: Workflow command scaffold for performance-optimization-pass in voice.
allowed_tools: ["Bash", "Read", "Write", "Grep", "Glob"]
---

# /performance-optimization-pass

Use this workflow when working on **performance-optimization-pass** in `voice`.

## Goal

Apply a series of performance optimizations and UX improvements across several components in a single commit.

## Common Files

- `VoiceInk/Views/Recorder/AudioVisualizerView.swift`
- `VoiceInk/Transcription/Processing/TranscriptionOutputFilter.swift`
- `VoiceInk/Transcription/Processing/WordReplacementService.swift`
- `VoiceInk/Transcription/Processing/FillerWordManager.swift`
- `VoiceInk/Transcription/Engine/TranscriptionPipeline.swift`
- `VoiceInk/Views/Recorder/MiniRecorderView.swift`

## Suggested Sequence

1. Understand the current state and failure mode before editing.
2. Make the smallest coherent change that satisfies the workflow goal.
3. Run the most relevant verification for touched files.
4. Summarize what changed and what still needs review.

## Typical Commit Signals

- Profile or audit the application to identify performance bottlenecks.
- Apply optimizations such as caching, reducing allocations, debouncing, and simplifying logic in relevant files.
- Make minor UX improvements (e.g., error banners, accessibility enhancements) as needed.
- Commit all related changes together with detailed descriptions.

## Notes

- Treat this as a scaffold, not a hard-coded script.
- Update the command if the workflow evolves materially.