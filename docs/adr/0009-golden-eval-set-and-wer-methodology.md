# 0009. Golden eval set and WER-based fine-tune methodology

## Status

Decided

## Context

ADR-0004 set the *trigger* for Phase 2 (2 weeks of use + ≥30 flagged sessions) but never specified how to actually measure whether fine-tuning worked. The flag-as-wrong signal (ADR-0003) is a good ongoing "is this bugging me" indicator, but it's the wrong tool for a rigorous before/after comparison — it's collected in the wild, isn't a fixed benchmark, and reusing it to fine-tune *and* to judge the fine-tune's own success risks measuring nothing but memorization.

Word Error Rate (WER) is the standard metric for this. The risk to guard against is data leakage: if the same audio used to fine-tune is also used to measure improvement, an improved score just proves the model memorized it, not that it generalized to new speech.

## Decision

1. **Build a golden eval set** — VoiceInk already retains every dictation's raw audio by default (`~/Library/Application Support/com.prakashjoshipax.VoiceInk/Recordings/*.wav`, 30+ files from a single day of testing) plus its own transcription attempt per session (the `Transcription` SwiftData model, linked by the same UUID). The audio-collection half of this is already happening passively — building the golden set is mostly **reviewing what's already on disk** and hand-verifying/correcting each transcript, not recording from scratch. Add a small number of deliberately-designed passages only to cover vocabulary or accent trouble spots that haven't naturally come up yet. Target roughly 20-30 verified pairs total.
2. **Split before touching anything else** — a **train subset** (reserved for actually fine-tuning later) and a **held-out eval subset** (never used in training, full stop). This is the guard against the memorization trap above.
3. **Baseline WER** — run the current candidates (Whisper large-v3, Parakeet V3) against the held-out eval subset *before* any fine-tuning. This doubles as the Whisper-vs-Parakeet bake-off already scoped informally — now with real numbers.
4. **Fine-tune** the stronger candidate on the train subset only, via LoRA (Parakeet, through `mlx-tune`) or DoRA (Whisper, through `mlx-lm` — DoRA isn't available for Parakeet via `mlx-tune` yet, only plain LoRA/QLoRA there).
5. **Re-measure WER on the exact same held-out eval subset** post-fine-tune. The delta is the trustworthy "did it improve, and by how much."
6. **Re-run the ADR-0002 smoke test too** — confirms fine-tuning didn't quietly regress basic reliability while chasing a WER number.

This is the first work item for Phase 2, ahead of any actual training — see CONTEXT.md.

## Consequences

- The golden eval set is a durable, reusable asset — every future fine-tune iteration (not just this one) gets measured against it, so improvement claims stay comparable over time.
- DoRA-vs-LoRA is no longer a separate open question — it follows directly from which model wins the baseline bake-off.
- Extra discipline required: it's tempting to fold flagged sessions into the eval set for convenience. Don't — flagged sessions are exactly the kind of data that should go in the *train* subset, precisely because they're known-hard examples. Mixing them into eval reintroduces the leakage risk this ADR exists to prevent.
- Newly discovered while writing this ADR: VoiceInk keeps every recording's audio indefinitely with no visible cleanup — already 30+ files from one day of testing. Not addressed here, but worth a retention policy before this becomes a real disk-usage problem (already flagged as an open risk in the original plan artifact).
