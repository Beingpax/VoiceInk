---
name: multi-module-bugfix-and-refactor
description: Workflow command scaffold for multi-module-bugfix-and-refactor in voice.
allowed_tools: ["Bash", "Read", "Write", "Grep", "Glob"]
---

# /multi-module-bugfix-and-refactor

Use this workflow when working on **multi-module-bugfix-and-refactor** in `voice`.

## Goal

Batch fixing multiple bugs and refactoring across several modules as part of an audit or code review.

## Common Files

- `VoiceInk/CoreAudioRecorder.swift`
- `VoiceInk/Models/LicenseViewModel.swift`
- `VoiceInk/Services/PolarService.swift`
- `VoiceInk/Transcription/Engine/TranscriptionPipeline.swift`
- `VoiceInk/Transcription/Engine/VoiceInkEngine.swift`
- `VoiceInk/Transcription/Processing/WordReplacementService.swift`

## Suggested Sequence

1. Understand the current state and failure mode before editing.
2. Make the smallest coherent change that satisfies the workflow goal.
3. Run the most relevant verification for touched files.
4. Summarize what changed and what still needs review.

## Typical Commit Signals

- Identify and list bugs or code smells across modules.
- Apply targeted fixes to each affected file (e.g., add error handling, refactor logic, improve resource management).
- Refactor code for maintainability and performance where necessary.
- Update related files to ensure consistency (e.g., models, services, views).
- Commit all changes in a single, descriptive commit.

## Notes

- Treat this as a scaffold, not a hard-coded script.
- Update the command if the workflow evolves materially.