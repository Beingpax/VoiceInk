# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

VoiceInk is a native macOS app (macOS 14.4+) that transcribes speech to text, optionally runs the result through an AI enhancement step, and pastes it into the frontmost app. This repo is a fork of `Beingpax/VoiceInk`; upstream does **not** accept PRs, and `origin` points at the user's fork (`dadanisme/VoiceInk`).

## Git workflow

**Never commit directly to `main`.** Always work on a separate feature branch (e.g. `feat/...`, `fix/...`, `chore/...`) and open a PR back to `main`. If you find yourself on `main` with changes staged or about to commit, stop and create a new branch first (`git checkout -b <branch>`).

## Build & Run

The project uses a Makefile wrapper around `xcodebuild`. The most common workflow is `make local` — it builds with ad-hoc signing (no Apple Developer account required), drops the app in `~/Downloads/VoiceInk.app`, and strips quarantine attributes.

- `make local` — build to `~/Downloads/VoiceInk.app` using `LocalBuild.xcconfig` + `VoiceInk.local.entitlements` + `LOCAL_BUILD` Swift flag. No CloudKit, no keychain-access-groups, no iCloud sync. Uses `.local-build/` as derived data.
- `make build` — debug build via normal xcodebuild (assumes signing is configured).
- `make dev` — `make build && make run`.
- `make run` — opens the most recently built `VoiceInk.app` (prefers `~/Downloads`, falls back to DerivedData).
- `make whisper` — clones `whisper.cpp` into `~/VoiceInk-Dependencies/` and builds `whisper.xcframework` (required on first checkout). `make setup` just checks/rebuilds this.
- `make clean` — removes `~/VoiceInk-Dependencies/` (forces whisper rebuild next time). Does **not** touch `.local-build/`.

**whisper.xcframework dependency lives outside the repo** at `~/VoiceInk-Dependencies/whisper.cpp/build-apple/whisper.xcframework`. Xcode resolves the reference from there. If Xcode can't find it, run `make whisper`.

### Testing

- Unit tests: `xcodebuild test -project VoiceInk.xcodeproj -scheme VoiceInk -destination 'platform=macOS'`
- Single test: append `-only-testing:VoiceInkTests/TestClassName/testMethod`
- The existing test targets (`VoiceInkTests`, `VoiceInkUITests`) are stubs — there is effectively no test suite yet. Don't rely on test-driven validation; verify by building and running the app.

### User build preference

The user **batches builds** — do not run `make local` between every task in a multi-task plan. Finish the code changes, then the user will build at the end. (If code-only verification is wanted mid-plan, `xcodebuild -quiet -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Debug CODE_SIGN_IDENTITY="" build` is a faster signal-check.)

## Architecture

### Entry point and composition

`VoiceInk/VoiceInk.swift` (`@main struct VoiceInkApp`) is the composition root. It builds a graph of `@StateObject` services in `init()` and wires them via `.environmentObject(...)` onto both `ContentView` (main window) and `MenuBarView` (menu bar extra). Key init order:

1. `ModelContainer` — SwiftData with **two stores**: `default.store` (Transcription) and `dictionary.store` (VocabularyWord, WordReplacement). In Release, the dictionary store uses CloudKit (`iCloud.com.prakashjoshipax.VoiceInk`); in `LOCAL_BUILD`, CloudKit is forced off. Has a persistent-fallback → in-memory-fallback chain with user-visible warnings.
2. `AIService` → `AIEnhancementService` (takes `aiService` + `modelContext`).
3. `WhisperModelManager` + `FluidAudioModelManager` → `TranscriptionModelManager` (unified facade).
4. `RecorderUIManager` + `VoiceInkEngine` (engine holds a `Recorder`; recorderUIManager + engine have a **circular reference** configured via `.configure(engine:recorder:)` — important when refactoring ownership).
5. `HotkeyManager`, `MenuBarManager`, `ActiveWindowService.shared.configure(with:)`, `ModelPrewarmService`.

`AppDelegate` handles URL-opening (`application(_:open:)`) and re-activation. If an open-file URL arrives during cold start, it's stashed in `pendingOpenFileURL` and processed by `ContentView.onAppear` — **do not create windows from AppDelegate on cold start** (comment on line 38 of AppDelegate.swift explains why).

### The transcription pipeline

`VoiceInkEngine` (Transcription/Core/VoiceInkEngine.swift, `@MainActor`) orchestrates recording state (`RecordingState` enum). When a recording stops, it calls into `TranscriptionPipeline.run(...)`, which executes this sequence:

`transcribe → TranscriptionOutputFilter → WhisperTextFormatter (optional) → WordReplacementService → PromptDetectionService → AIEnhancementService.enhance (optional) → save to SwiftData → paste via CursorPaster → dismiss recorder`

Each step checks `shouldCancel()` and bails with `onCleanup()` if the user cancelled. Cancellation is always possible mid-pipeline.

### Transcription service dispatch

`TranscriptionServiceRegistry` maps a `ModelProvider` (enum in `Models/TranscriptionModel.swift`) to one of four services:

- **local** (`.local`) → `LocalTranscriptionService` (whisper.cpp via `LibWhisper.swift`)
- **fluidAudio** (`.fluidAudio`, displayed as "Parakeet") → `FluidAudioTranscriptionService`
- **nativeApple** (`.nativeApple`) → `NativeAppleTranscriptionService` (SpeechAnalyzer)
- everything else (`groq`, `elevenLabs`, `deepgram`, `mistral`, `gemini`, `soniox`, `speechmatics`, `custom`) → `CloudTranscriptionService`

Streaming is a **parallel path**: `TranscriptionServiceRegistry.createSession(for:)` returns a `StreamingTranscriptionSession` (wrapping a provider in `Transcription/Streaming/`) for models listed in `supportsStreaming(model:)`, or a `FileTranscriptionSession` otherwise. Streaming-only models have a `batchFallbackModel(for:)` mapping so batch transcription still works (e.g. Soniox `stt-rt-v4` → `stt-async-v4`).

Adding a new transcription provider: (1) add the case to `ModelProvider`, (2) add a `CloudModel`/custom-struct entry to `PredefinedModels`, (3) add a service implementing `TranscriptionService`, (4) wire it in `TranscriptionServiceRegistry`, (5) if streaming, add a `StreamingTranscriptionProvider` and list the model name in `supportsStreaming`.

### AI enhancement

`Services/AIEnhancement/` — `AIService` owns the model/provider selection and API calls; `AIEnhancementService` composes it with prompt selection (predefined + custom from SwiftData), output filtering, and prompt-detection hooks. Apple Intelligence (`AppleIntelligenceService`) and local CLI (`LocalCLIService`, e.g. `claude`/`codex`) are enhancement providers — they run the text, not audio.

### Power Mode

`PowerMode/` implements per-app/per-URL auto-configuration: `ActiveWindowService` watches the frontmost app, `PowerModeValidator` matches configs against app bundle id or URL, `PowerModeSessionManager` applies the matched config (transcription model, AI prompt, enhancement on/off) for the current recording. Config is serialized to UserDefaults via `PowerModeConfig`.

### UI surfaces

Three recorder UIs (`Views/Recorder/`) — a floating pill (`MiniRecorderPanel`), a notch overlay (`NotchRecorderPanel`), and menu bar flows. All three use `ActiveScreenResolver.currentActiveScreen()` to decide which display to appear on (AX focused-window → cursor → NSScreen.main → fallback). Notifications and the dictionary quick-add panel also route through `ActiveScreenResolver` — if you're adding a new floating panel, use the same resolver rather than `NSScreen.main` directly (multi-display correctness).

### Logging

All logging uses `os.Logger` with subsystem `com.prakashjoshipax.voiceink` and a per-file `category`. When debugging, filter `log stream --predicate 'subsystem == "com.prakashjoshipax.voiceink"'`. `FluidAudio`'s own logs use subsystem `fluidaudio`.

## Local vs Release build differences

The `LOCAL_BUILD` Swift compilation flag gates behavior when building without a Developer account:

- CloudKit is disabled for the dictionary store (`VoiceInk.swift` ~line 201–211).
- `VoiceInk.local.entitlements` drops `icloud-*`, `aps-environment`, `keychain-access-groups`, and the MediaRemote mach-lookup exceptions.
- No Sparkle auto-update; user has to pull + rebuild.

Guard any new CloudKit/keychain-group/push-notification code with `#if LOCAL_BUILD` when adding features, or the local build will break silently.

## Conventions and gotchas

- `VoiceInkEngine` is `@MainActor` — its methods and stored properties must be reached from the main actor. When calling into it from a detached `Task`, use `await MainActor.run { ... }` or make the call site async.
- SwiftData `ModelContext` is the `container.mainContext` — passed into the engine, pipeline, services that need it. Do not create secondary contexts unless you know what you're doing (CloudKit sync lives on the dictionary store's context).
- Whisper model files live in `~/Library/Application Support/com.prakashjoshipax.VoiceInk/WhisperModels/`. Recordings live in `~/Library/Application Support/com.prakashjoshipax.VoiceInk/Recordings/` and are garbage-collected by `AudioCleanupManager`.
- `Sandbox` is **off** (`com.apple.security.app-sandbox = false`). The app relies on AX (accessibility) + automation + screen-capture entitlements for Power Mode, cursor pasting, and focused-window detection.
- `URLCache.shared` is disabled at launch to prevent API responses from hitting disk (Cache.db) — preserve this when adding new HTTP clients.
- `docs/superpowers/` is gitignored — that's where the user's brainstorming/plan artifacts from the superpowers skills live. Don't commit anything from there.

## Project MCP servers

`.mcp.json` declares three MCPs scoped to this repo. First time Claude Code opens the repo, it will prompt to approve them.

- **XcodeBuildMCP** (`getsentry/XcodeBuildMCP`) — run `xcodebuild` via MCP, stream logs, target a single test. Complements the Makefile; use it for surgical test runs and log tailing, not full builds.
- **apple-docs** (`kimsungwhee/apple-docs-mcp`) — query Apple developer docs (SwiftUI, SwiftData, AVFoundation, AppKit, AX) without a web round-trip. Use before WebSearch when looking up an Apple API.
- **swiftlens** (`swiftlens/swiftlens`) — Swift semantic navigation (definitions, references, hover, symbol search). Wraps `sourcekit-lsp` with ~15 tools. **Caveats:** upstream is archived (read-only since 2025-07) and the license is "free for personal use; commercial use requires a license" — fine for personal fork work. Cross-file queries need a pre-built index store; since this is an Xcode project, generate it with a normal `make build` or `make local` (Xcode writes to `~/Library/Developer/Xcode/DerivedData/<project>/Index.noindex/DataStore` on every build). If swiftlens returns empty results, rebuild first; if still empty, fall back to Grep.

XcodeBuildMCP + apple-docs run via `npx` (Node 22 in the user's nvm); swiftlens runs via `uvx` (Python 3.10+). No global installs required.

## Installed Claude Code plugins

The user has these plugins installed globally (available in all sessions, not repo-scoped):

- **superpowers** — workflow skills (brainstorming, writing-plans, executing-plans, TDD, systematic-debugging, verification-before-completion, etc.). Follow skill instructions exactly when invoked.
- **context7** — up-to-date library/framework docs lookup. Use when you need current API references for third-party libraries.
- **commit-commands** — `/commit`, `/commit-push-pr`, `/clean_gone` for git workflow.

## Session context

- Auto-memory is persisted under `~/.claude/projects/.../memory/` — check `MEMORY.md` at session start for session-spanning facts (build batching, gitignored paths, etc.).
