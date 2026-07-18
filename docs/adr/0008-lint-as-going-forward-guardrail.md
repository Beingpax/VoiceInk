# 0008. CI and lint as going-forward guardrails, not retroactive cleanup

## Status

Decided

## Context

A background check found this codebase has 0% real test coverage (the shipped `VoiceInkTests.swift` is unmodified Xcode boilerplate), no CI, and no lint config across 310 Swift files. Concern raised: building our own changes (telemetry hooks, fine-tuned model swap) on top of an untested codebase risks silent breakage.

Two ways to respond: retroactively clean up/test the existing 310 files (187 once the 123 SwiftUI View files are excluded as out of scope), or add guardrails that catch *new* problems without churning code we don't otherwise need to touch. Running SwiftLint with default rules against the existing code produced 117 errors and 692 warnings — fixing all of that now would mean editing the majority of the codebase for style alone, which is itself a large source of regression risk, directly contradicting the goal of not destabilizing the app.

## Decision

- **CI**: a GitHub Actions workflow (`.github/workflows/build.yml`) builds the project via `make local` and runs the test target on every push/PR to `main`. Catches compile breaks and test regressions automatically, going forward.
- **Lint**: `.swiftlint.yml` with default rules, running in CI as report-only (`continue-on-error: true`). Existing violations are not fixed in bulk. Clean up a file's lint violations opportunistically when it's already being touched for a real change — never as a standalone bulk edit.

## Consequences

- Immediate safety net for our own future changes (this is the actual goal — see CONTEXT.md), without a large, risky cleanup pass over code we didn't write and don't need to modify.
- Lint violation count will only trend down slowly, file by file, as we touch things — that's intentional, not a gap to "fix later" in one pass.
- Real unit test coverage for existing application logic (Models/Modes/Services/Transcription, excluding Views) is tracked separately as a triaged, prioritized effort — see the corresponding GitHub issue — rather than folded into this ADR's scope.
