# PRD

Scoped-but-not-yet-issued work. Items land here once discussed and resolved (typically via a grilling session); each is split into GitHub Issue(s) for implementation and removed from here once filed. See `CONTEXT.md` for vocabulary and `docs/adr/` for settled architectural decisions.

## Golden eval set / WER tooling UI integration

**Status:** resolved via grilling session (2026-07-19). Ready to convert to GitHub Issue(s) once confirmed.

**Problem:** the golden eval set review tool (#15) and baseline WER harness (#16) currently live in a separate `GoldenEvalSetWindowController` window with its own menu bar entry and a duplicated `NavigationSplitView` list+detail layout, rather than being deeply integrated into VoiceInk's existing History UI. Explicit ask: a single, deeply-integrated interface, not a bolted-on second window.

### UI structure

- **Entry point:** a second sidebar section/tab inside the existing History window — "Golden Eval Set", alongside the default section — not a filter toggle on the same list, not a toolbar overlay panel, not a separate `NSWindow`.
- **List:** reuses the existing `TranscriptionListItem`-style list component, filtered to candidates with audio, rather than a distinct list implementation.
- **Ground-truth editor:** renders inline in the existing `TranscriptionDetailView`/`AudioPlayerView` detail area — the same detail view regardless of which sidebar section you're browsing from — not a separate detail layout. Contents: editable ground-truth text (defaulting to VoiceInk's original transcript) + a "Mark Verified" action. No train/eval/control picker in the UI — categorization is automatic (see below).
- **Menu bar:** the standalone "Golden Eval Set" entry is dropped entirely. Only "History" remains; the Golden Eval Set section is reached from inside that one window.
- **WER trigger:** "Run Baseline Evaluation" becomes a toolbar button scoped to the Golden Eval Set sidebar section (replacing the current window-level toolbar button in `GoldenEvalSetWindowController`).

### Categorization — three groups, not a manual picker or a flat random split

Assignment happens automatically the moment a recording is marked verified, based on whether the ground truth needed a correction:

- **Unedited** (`groundTruthText` exactly matches VoiceInk's original transcript, `enhancedText ?? text`) → always **Control**. Not a percentage — Control's size is whatever fraction of recordings needed zero fixes. Purpose: regression check — confirms fine-tuning doesn't degrade cases the model already handled correctly.
- **Edited** (`groundTruthText` differs from the original) → randomly split, fixed recorded seed:
  - **60% Train** — used to fine-tune.
  - **40% Eval** — held out, used to measure whether fine-tuning improved the error cases. Not frozen — keeps absorbing newly-verified edited recordings over time (explicit choice, against the recommendation to freeze it for measurement stability). Mitigation: `WEREvaluationResult` already keys each result by `goldenEvalEntryId` per run (`runLabel`), so a future "compare runs" feature computes before/after WER on the *intersection* of entries present in both runs rather than "whatever's in eval right now."
- **Random seed:** a fixed constant committed in source (not generated-and-persisted) — deterministic and "recorded" simply by being in git history.

This needs a third case added to the `GoldenEvalSplit` enum (currently `train`/`eval` only) — becomes `train` / `eval` / `control`.

### Model comparison ("different versions of VoiceInk in parallel, base as control")

Resolved to **offline model-variant comparison**, not live parallel app instances — this is what the WER harness (#16) already does (`WERBaselineHarness`, `TranscriptionServiceRegistryTranscriber`). Changes needed:
- Extend from the two hardcoded baseline candidates (`baselineModelDisplayNames = ["Large v3", "Parakeet V3"]`) to an arbitrary candidate list.
- Model selection per run: a multi-select checklist of currently-downloaded models (`TranscriptionModelRegistry.models`, filtered to what's locally available) — not a fixed configured control/treatment pair, not "every downloaded model automatically."

### Resulting shape (for implementation)

1. `TranscriptionHistoryView`'s sidebar gains a "Golden Eval Set" section, listing the existing list-item component filtered to candidates with audio.
2. `TranscriptionDetailView` gains an inline "Golden Eval Set" panel (ground-truth text editor + "Mark Verified"). On verify, new logic (e.g. `GoldenEvalSetService.verify`) compares the edited text to the original, assigns Control (unedited) or randomly assigns Train/Eval at 60/40 (edited, fixed seed), and persists a `GoldenEvalEntry`.
3. `GoldenEvalSplit` gains a `control` case.
4. `GoldenEvalSetWindowController` and its menu bar entry are removed entirely.
5. The WER "Run Baseline Evaluation" trigger moves into the Golden Eval Set section's toolbar; candidate models become a multi-select checklist instead of the current hardcoded pair.
6. Deferred, not part of this item: the "compare runs" (intersection-based before/after WER) feature — worth its own PRD entry once actually needed, post first fine-tune.
