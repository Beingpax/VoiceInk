# VoiceInk Enhancement PR: Performance, Local AI, and Intelligent Vocabulary

## Overview

This PR represents a collaborative effort between Jeff (product direction, testing, and
quality validation) and Claude Code (architecture, implementation, and iterative refinement).
Every feature was conceived by Jeff based on real-world usage of VoiceInk, then designed and
implemented by Claude Code through extensive pair-programming sessions. Jeff tested each
change against live transcription workflows, identified issues, and directed the fixes --
a tight feedback loop that produced production-quality results.

The changes span 56 files with ~7,800 lines added across performance improvements, a
complete local AI integration, an intelligent vocabulary system, and numerous UX refinements.

---

## What Changed

### 1. Performance, Reliability, and UX Foundation

**Commits:** `d2306eb`, `0e84ebf`, `e1aec94`

- Rewrote hotkey management (`HotkeyManager.swift`) for more reliable keyboard shortcut
  handling
- Improved `CursorPaster` with editable text field detection -- VoiceInk now identifies
  whether the target field can accept typed input and adapts its paste strategy accordingly
- Added screen selection support and type-out paste mode for applications that don't
  support standard clipboard paste
- "Type Last Transcription" feature for re-inserting previous results
- Fixed `CancellationError` handling during transcription so cancelled recordings don't
  produce error alerts
- Established `make local` build pipeline with Apple Development certificate signing for
  stable local development builds

### 2. Background Enhancement Queue

**Commit:** `30b996d`

Jeff identified that waiting for AI enhancement before pasting was disruptive to workflow.
The solution: paste raw transcription immediately, then enhance in the background.

- New `EnhancementQueueService` processes transcriptions asynchronously after paste
- Enhanced results appear in History for review and re-use
- Post Processing settings view with toggles for background enhancement
- Background enhancement runs independently of the main transcription flow

### 3. Vocabulary Extraction Pipeline

**Commits:** `30b996d`, `09b7368`, `f36ab51`

Jeff wanted the app to learn from its own corrections -- if the AI keeps fixing the same
word, VoiceInk should suggest adding it to the dictionary.

- Built `VocabularyDiffEngine` using LCS (Longest Common Subsequence) alignment to compare
  raw Whisper/Parakeet output against AI-enhanced text and identify correction patterns
- `VocabularySuggestionService` runs the diff engine on every transcription, tracking
  correction frequency and surfacing suggestions when patterns recur
- `VocabularySuggestion` model with occurrence counting and date tracking
- `VocabularySuggestionsView` with approve/dismiss workflow -- one click adds a word to
  the dictionary
- `CommonWordsService` with frequency lists for 5 languages (en, de, es, fr, pt) to filter
  out common words that don't belong in a custom vocabulary
- Vocabulary words injected into the Whisper/Parakeet transcription prompt to bias speech
  recognition toward correct spellings
- Separated Post Processing settings into its own view for clearer organization

### 4. MLX-LM Local AI Provider

**Commits:** `a8fdcbe`, `6bdc91e`

Jeff wanted VoiceInk to work fully offline. Claude Code integrated Apple's MLX framework
for local inference on Apple Silicon.

- New `LocalMLXService` with connection management, model discovery, and server lifecycle
- New `LocalMLXClient` implementing OpenAI-compatible HTTP client for mlx-lm server
- Auto-start: VoiceInk launches the mlx-lm server process automatically when MLX-LM is
  selected as the AI provider, including model loading and health polling
- Server binary detection at `/opt/homebrew/bin/mlx_lm.server` with
  `KMP_DUPLICATE_LIB_OK=TRUE` environment variable for compatibility
- Full integration into the provider selection UI alongside cloud providers
- Settings view for base URL, model selection, and server management

### 5. Phonetic Hints System

**Commits:** `54a6351`, `12f4de7`, `59edf91`

This was born from Jeff's testing of the local 7B model. He noticed that while Gemini could
correct "voicing" to "VoiceInk" using world knowledge, the smaller model needed explicit
guidance. Jeff proposed adding phonetic mistranscription mappings to vocabulary entries.

**Manual hints:**
- Added `phoneticHints` field to `VocabularyWord` model
- Format in AI prompt: `VoiceInk (often heard as: voicing, voice ink, voice inc)`
- Expandable editor on each vocabulary word chip with save/cancel
- Visual indicator: words with hints show them in orange text below the word name, with an
  orange border on the chip

**Auto-generation:**
- `PhoneticHintMiningService` mines transcription history by comparing raw vs enhanced text
  across all transcriptions, finding patterns where the AI consistently corrects the same
  mishearings for vocabulary words
- Multi-layered plausibility filter (`isPlausiblePhoneticHint`) to reject false patterns:
  - Morphological variant detection (skill/skilled, paste/pasting)
  - Abbreviation rejection with plural handling (devs/developers)
  - Number-to-text conversion filtering (five-second/5-second)
  - Containment detection with punctuation splitting (have.net/net)
  - Slash-command format rejection (slash ideation//ideation)
  - Bigram Dice similarity threshold (0.30) for orthographic plausibility
- "Generate Hints" button in Dictionary view with review sheet -- user approves/rejects
  each discovered hint before it's applied
- "Auto-generate Phonetic Hints" toggle in Post Processing settings for real-time discovery
- When approving vocabulary suggestions, the raw mishearing is automatically carried as the
  initial phonetic hint

**Overcorrection discovery and fix:**

Jeff tested extensively and discovered that phonetic hints containing common English words
(claw, cloud, clawed) caused both local and cloud models to overcorrect. For example,
"the dog clawed me" was being changed to "the dog claude" because "clawed" was listed as a
hint for "claude." Claude Code ran systematic tests through the Gemini CLI, progressively
removing hints to identify the threshold. The finding: hints should only use words that
aren't valid English (e.g., "voiceync" for VoiceInk, "chambois" for chezmoi). Common words
as hints override the model's contextual understanding.

### 6. Transcription vs Enhancement Vocabulary Split

**Commits:** `12f4de7`

Jeff asked whether we could give the transcription model (Parakeet/Whisper) hints the same
way we give the enhancement model. Claude Code's analysis revealed:

- The transcription model uses the prompt as conditioning text, not instructions
- `(often heard as: claw, clawed)` is meaningless to Whisper/Parakeet -- it just sees those
  as words that should appear in output
- The annotation text wastes conditioning tokens and adds noise

Solution: `CustomVocabularyService` now provides two formats:
- `getTranscriptionVocabulary()` -- bare word list for biasing speech recognition
- `getCustomVocabulary()` -- full annotations with phonetic hints for AI enhancement

### 7. Menu Bar Provider Fix

**Commits:** `12f4de7`, `ca1de86`

Jeff reported that Ollama and MLX-LM weren't showing in the menu bar's AI provider selector
despite being configured. Claude Code traced the issue to two root causes:

- `ollamaService` and `localMLXService` were `lazy var` (not `@Published`), so changes to
  their `isConnected` property didn't trigger SwiftUI re-renders
- No connection check ran at startup -- `isConnected` stayed `false` until the user visited
  settings

Fix: Changed to `let` properties with Combine `objectWillChange` forwarding, added startup
connection checks and model list refresh.

### 8. Experiment Documentation

**Commit:** `844ca9f`, updated in `12f4de7`

Comprehensive documentation of 10 experiments conducted during development, covering:
- Ollama vs MLX-LM speed comparison (MLX is 5-10x faster on Apple Silicon)
- Model size vs quality (3B vs 7B vs Gemini)
- Phonetic distance limits without hints
- Gemma 3 4B evaluation (underperformed Qwen 7B for this task)
- Phonetic hints effectiveness (7B went from 2/4 to 3/4 corrections)
- Prompt size impact (compact prompts improve small model accuracy)
- Context awareness toggle impact
- Phonetic hint overcorrection analysis
- Transcription model comparison (Parakeet V2 vs Large v3 Turbo)
- Vocabulary format split rationale

---

## Files Changed (56 files, +7,779 / -946)

### New Files
| File | Purpose |
|------|---------|
| `Services/EnhancementQueueService.swift` | Background AI enhancement processing |
| `Services/VocabularyDiffEngine.swift` | LCS-based correction pattern extraction |
| `Services/VocabularySuggestionService.swift` | Automatic vocabulary suggestion pipeline |
| `Services/CommonWordsService.swift` | Common word frequency filtering |
| `Services/PhoneticHintMiningService.swift` | Phonetic hint discovery and plausibility filtering |
| `Services/LocalMLXService.swift` | MLX-LM connection, model discovery, server lifecycle |
| `Services/LocalMLXClient.swift` | OpenAI-compatible HTTP client for mlx-lm |
| `Services/EditableTextFieldChecker.swift` | Text field detection for paste strategy |
| `Services/LastTranscriptionService.swift` | Re-insert previous transcription |
| `Models/VocabularySuggestion.swift` | SwiftData model for vocabulary suggestions |
| `Views/PostProcessingSettingsView.swift` | Background enhancement and extraction settings |
| `Views/Dictionary/VocabularySuggestionsView.swift` | Suggestion approval/dismissal UI |
| `Resources/CommonWords/{en,de,es,fr,pt}.txt` | Common word lists for 5 languages |
| `docs/local-model-experiments.md` | Experiment results and recommendations |
| `docs/pr-description.md` | This document |

### Modified Files
| File | Changes |
|------|---------|
| `AIService.swift` | MLX-LM/Ollama provider integration, Combine observation forwarding, startup connection checks |
| `AIEnhancementService.swift` | Background enhancement mode, vocabulary injection into prompts |
| `CustomVocabularyService.swift` | Phonetic hint formatting, transcription vs enhancement vocab split |
| `VocabularyWord.swift` | Added `phoneticHints` field |
| `VocabularyView.swift` | Phonetic hint UI, Generate Hints button, review sheet, visual indicators |
| `WhisperState.swift` | Refactored transcription flow, vocabulary prompt injection |
| `WhisperState+UI.swift` | Context prompt updates, bare vocabulary for transcription model |
| `HotkeyManager.swift` | Rewritten for reliability |
| `CursorPaster.swift` | Text field detection, type-out paste |
| `TranscriptionHistoryView.swift` | Enhanced history display |
| `SettingsView.swift` | New settings sections for local AI and post-processing |
| `MenuBarView.swift` | Provider and model selection in menu bar |
| `APIKeyManagementView.swift` | MLX-LM and Ollama configuration UI |

---

## Testing Approach

All features were tested through live transcription workflows:

1. **Vocabulary extraction**: Verified that AI corrections are detected, deduplicated,
   and surfaced as suggestions with correct occurrence counting
2. **Phonetic hints**: Tested with challenging word pairs (Claude/clawed/clod/clot,
   VoiceInk/voicing/voice ink, chezmoi/shamua) across both local 7B and Gemini models
3. **Overcorrection validation**: Systematically tested hint removal using Gemini CLI to
   find the threshold where hints cause more harm than good
4. **Local AI**: Verified MLX-LM server auto-start, model loading, and enhancement quality
   with Qwen 2.5-7B-Instruct-4bit
5. **Transcription model comparison**: Same test corpus run through Parakeet V2 and Large
   v3 Turbo to characterize each model's strengths
6. **Menu bar integration**: Verified provider and model lists populate at startup
7. **Background enhancement**: Confirmed raw text pastes immediately while enhancement
   processes asynchronously

## How It Was Built

This PR was developed through iterative pair-programming between Jeff and Claude Code (Opus).
Jeff identified problems and opportunities from his daily use of VoiceInk, described what he
wanted, and tested each iteration. Claude Code explored the codebase, designed solutions,
implemented the code, ran builds, deployed to `/Applications`, and refined based on Jeff's
feedback. The phonetic hint plausibility filter alone went through 4 iterations of
refinement, each driven by Jeff testing with real speech and identifying cases where the
filter was too aggressive or too permissive. The experiment documentation captures the
empirical results that guided every design decision.
