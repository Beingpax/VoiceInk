# VoiceInk Architecture — Current State

Written 2026-07-19, reflecting the codebase as of commit `930d2c8`. See `CONTEXT.md` for vocabulary, `docs/adr/` for why each decision was made, `PRD.md` for what's planned but not yet built.

## TL;DR — is it learning?

**No.** There is no active fine-tuning or learning loop anywhere in this codebase today. Grepped for LoRA, fine-tuning, `mlx-lm`, `mlx-tune`, and model-training code paths — the only hits are comments describing a *future*, not-yet-triggered plan (ADR-0004) and one unrelated Settings string about manually importing an already fine-tuned model file. Nothing in the app modifies model weights, and nothing accumulates a correction history that feeds back into transcription automatically.

If dictation feels like it's improving, based on your own actual usage data (100% Parakeet V3 this week, confirmed via PostHog), the most likely explanations are **not** the app adapting:

- **Whisper prompt biasing is inactive for you** — it only applies to Whisper, and you're using Parakeet.
- **Custom Vocabulary's only pathway into transcription is inactive** — it feeds the AI Enhancement LLM prompt, and you explicitly skipped configuring an LLM enhancement provider during onboarding. No provider configured means no enhancement pass runs at all, for anyone, regardless of vocabulary entries.
- **Word Replacement** — only active if you've manually added find/replace pairs in Settings. Possible, but requires deliberate setup, not automatic learning.
- Most plausible: **you're adapting** — clearer enunciation, more consistent phrasing, getting used to mic placement/environment — and Parakeet is simply doing well on the kind of speech you're now giving it.

The rest of this document explains why, in detail, and what's actually been built so far.

## 1. The dictation pipeline (what happens when you talk)

```
Hotkey/PTT → CoreAudioRecorder → audio buffer
    → TranscriptionServiceRegistry.transcribe(audioURL:model:context:)
        → routes by model.provider:
            .whisper      → WhisperTranscriptionService (whisper.cpp, GGML models, local)
            .fluidAudio   → FluidAudioTranscriptionService (Parakeet/Nemotron, local, via FluidAudio)
            .nativeApple  → NativeAppleTranscriptionService (macOS Speech framework)
            (other)       → CloudTranscriptionService (external API providers)
    → raw transcript text
    → TranscriptionOutputFilter.filter()      — strips model artifacts
    → ParagraphFormatter.format()             — if formatting enabled
    → WordReplacementService.applyReplacements() — literal find/replace (see §2.2)
    → [optional] AIEnhancementService pass    — LLM cleanup, only if configured (see §2.1/2.4)
    → Transcription persisted to SwiftData
    → SessionMetricRecorder.recordRecorderSession() → SessionMetric persisted + PostHog event
    → CursorPaster.pasteAtCursor() / clipboard
```

Model selection (which of Whisper/Parakeet/Apple/Cloud runs) is controlled by `TranscriptionModelManager` and the active `ModeConfig`, not chosen automatically based on accuracy — you (or a Mode) pick the model.

## 2. The four mechanisms that look like adaptation (none of them are)

All four are **static, manually-configured settings** — they don't change based on what VoiceInk gets right or wrong. None of them "learn."

### 2.1 Custom Vocabulary / Personal Dictionary
`CustomVocabularyService.swift`, `VocabularyWord` (SwiftData model). Words you add are concatenated into a string — `"Important Vocabulary: word1, word2, ..."` — and injected into the **AI Enhancement LLM prompt** (`AIEnhancementService.swift`), as an instruction telling the LLM to fix phonetically-close mistakes against that list.

Critically: this is **not** decoding-time bias for Whisper or Parakeet. It only takes effect during the AI Enhancement pass, and that pass only runs if `AIEnhancementService.isConfigured(for:)` finds a configured LLM provider — which you explicitly skipped setting up. So right now, any vocabulary words you've added are inert.

### 2.2 Word Replacement
`WordReplacementService.swift`, `WordReplacement` (SwiftData model). A literal, case-insensitive find/replace table applied to the transcript **after** transcription (`TranscriptionPipeline.swift`), longest-match-first. Deterministic string substitution — if you've manually added pairs (e.g. "VoiceInk" → "VoiceInk", fixing a common mis-transcription), those apply every time, unconditionally. No fuzzy matching, no confidence scoring, nothing adaptive — just a lookup table you maintain by hand in Settings.

### 2.3 Whisper prompt biasing
`TranscriptionRequestContext` / `TranscriptionService.swift`. A raw string you type once (`UserDefaults["TranscriptionPrompt"]`) gets passed as Whisper's initial decoding prompt — but `TranscriptionRequestContext.scoped(to:)` strips this to `nil` for any non-Whisper provider. Since your real usage is 100% Parakeet V3, this mechanism is currently doing nothing for you regardless of whether it's set.

### 2.4 Modes
`ModeConfig`, `ModeRuntimeResolver`. A Mode is a named bundle of the *static* settings above (prompt, formatting, enhancement provider, vocabulary scope) that activates based on the frontmost app/website or a manual switch. Selecting a Mode doesn't create new adaptive behavior — it just changes *which* of the fixed settings above apply to a given session.

## 3. What's actually been built this session (measurement infrastructure, not learning)

Everything below exists to eventually let a *real* fine-tune happen safely and be measured rigorously — none of it changes transcription behavior today.

### 3.1 Telemetry (ADR-0003)
`TelemetryService.swift` — PostHog Cloud (EU), configured at app launch (guarded against firing during test runs — see §3.1.1). Two events:
- `session_metric_recorded` — fired once per completed transcription from `SessionMetricRecorder`, mirrors the local `SessionMetric` SwiftData record (word count, audio/transcription duration, speed factor, model name, mode, enhancement stats). Never includes transcript text or audio.
- `session_flagged` — the **Flag event** (CONTEXT.md): a one-keystroke "this came out wrong" marker (global shortcut `.flagLastTranscription`, or a toggle button in the History audio player toolbar), the primary accuracy signal for the ADR-0004 fine-tune trigger. Just a transcription ID, nothing else.

#### 3.1.1 A real bug worth knowing about
Earlier today, running `xcodebuild test` accidentally leaked fake telemetry events into production PostHog, because `VoiceInkTests` runs *hosted inside the real VoiceInk.app process* — so `VoiceInkApp.init()`, including telemetry setup, genuinely executes on every test run. Found and fixed twice (the first fix, checking `XCTestConfigurationFilePath`, was itself unreliable — confirmed via PostHog data showing a leak *after* that fix was live). Current guard checks two independent signals (the env var, and whether `VoiceInkTests.xctest` is loaded into the process) and applies at both `configure()` and every individual capture call, with logging at each decision point. 12 of the 47 events in the project before the fix were confirmed test artifacts and have been identified/excluded from analysis; real production data starts cleanly from that point on.

### 3.2 Golden eval set (ADR-0009)
`GoldenEvalEntry` (SwiftData), `GoldenEvalSetService`, reviewed via `GoldenEvalSetView` (currently its own window, menu bar → "Golden Eval Set" — planned to fold into the History window, see `PRD.md`).

VoiceInk already saves every recording's audio to disk (`~/Library/Application Support/com.prakashjoshipax.VoiceInk/Recordings/`), so this tool is a browse-and-verify UI over what's already there, not a recorder. For each candidate: listen, correct the transcript if VoiceInk got it wrong, click "Mark Verified." Categorization is then **automatic**, not picked manually:

- Transcript needed no correction → **Control** (a regression check — after a future fine-tune, do previously-correct recordings still transcribe correctly?)
- Transcript needed a correction → deterministically split **60% Train / 40% Eval**, via a fixed seed (`GoldenEvalSetService.trainEvalSeed`) hashed per-recording (FNV-1a, not Swift's randomized `Hashable`, so the split is reproducible across app runs)

The eval split is deliberately **not frozen** — it keeps absorbing newly-verified corrected recordings over time. Before/after WER comparisons are expected to use the *intersection* of entries present in both measurement runs (`WEREvaluationResult.runLabel` groups a pass), not "whatever's in eval right now."

### 3.3 WER measurement (ADR-0009)
`WordErrorRateCalculator` — standard word-level Levenshtein WER (substitutions + deletions + insertions, over reference word count), case-insensitive and punctuation-stripped.

`WERBaselineHarness` — runs eval-split entries through candidate models (currently hardcoded to Whisper Large v3 + Parakeet V3; planned to become a multi-select of downloaded models per `PRD.md`), scores each against the verified ground truth, persists one `WEREvaluationResult` row per (entry, model, run). Model invocation is behind an injectable protocol so the orchestration logic is unit-tested without needing real ML weights loaded.

**No real WER number exists yet** — zero recordings have been reviewed through the golden eval tool so far (36 real dictation sessions exist and are reviewable, but the review step is manual and hasn't started).

### 3.4 The eventual fine-tune (planned, ADR-0004 — not implemented)
Trigger condition: 2 weeks of use **and** ≥30 flagged sessions, whichever comes later. Neither condition is close to being met (0 flags recorded so far). When triggered, the plan (not yet built) is LoRA/DoRA fine-tuning via `mlx-lm` (Whisper) or `mlx-tune` (Parakeet, LoRA/QLoRA only — no DoRA support confirmed there yet) on the Train-split recordings, then re-measuring WER on the same Eval-split entries to see whether it actually helped, before deciding whether to adopt the fine-tuned weights.

## 4. Data model (SwiftData, local-only unless noted)

| Model | Purpose |
|---|---|
| `Transcription` | Every dictation session — raw text, enhanced text, audio file reference, model used, mode, `flagged` |
| `SessionMetric` | Derived stats per transcription, mirrored to PostHog as `session_metric_recorded` |
| `GoldenEvalEntry` | One per human-verified recording — ground truth text + auto-assigned Control/Train/Eval |
| `WEREvaluationResult` | One per (eval entry, candidate model, measurement run) |
| `VocabularyWord` | Custom Vocabulary entries (see §2.1) |
| `WordReplacement` | Find/replace pairs (see §2.2) |
| `ModeConfig` | Named settings bundles (see §2.4) |

Everything above is local SwiftData, except `SessionMetric` and the Flag event, which are additionally mirrored to PostHog per ADR-0003. Audio and transcript text never leave the device.

## 5. Governance — where decisions and plans live

- **`docs/adr/`** — settled architectural decisions, with the why. Read before changing behavior an ADR covers.
- **`CONTEXT.md`** — the project's vocabulary/glossary.
- **`PRD.md`** — scoped-but-not-yet-issued work, resolved via grilling sessions, converted to GitHub Issues once ready.
- **GitHub Issues** (`aadhar-build/VoiceInk`) — actionable, ready-to-implement work.
- **Testing discipline**: test-protected editing (confirm coverage before touching a file, baseline → change → re-verify), Swift Testing (`VoiceInkTests`), CI via GitHub Actions (`.github/workflows/build.yml`, ~11-13 min, 25 min timeout), SwiftLint as a non-blocking report (ADR-0008).
