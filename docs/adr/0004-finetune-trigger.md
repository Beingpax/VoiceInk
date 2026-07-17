# 0004. Fine-tune trigger: time-box + volume, whichever is later

## Status

Decided

## Context

Whisper's `large-v3` already handles Indian English reasonably well out of the box; the immediate, zero-cost lever is Personal Dictionary + prompt biasing (Phase 1), not fine-tuning. A LoRA fine-tune (Phase 2) is real engineering effort — it shouldn't start on a hunch, but it also shouldn't wait forever on a vague "someday."

Three trigger shapes were considered:

- **Flag-rate threshold** (e.g. >15% of sessions flagged wrong over a rolling week) — reacts fast, but noisy at low volume early on.
- **Time-box + volume** — after 2 weeks of real daily use **and** at least ~30 flagged sessions accumulated, whichever comes later.
- **Manual call** — no formal trigger, just periodic judgment looking at the dashboard.

## Decision

Time-box + volume: **2 weeks of real daily use AND ≥30 flagged sessions**, whichever condition is satisfied later.

## Consequences

- Guarantees both realistic usage patterns (not a burst of testing) and enough labeled examples to make a LoRA fine-tune worthwhile — 30 flagged sessions is a reasonable floor for a useful adaptation set.
- If flags are rare (dictionary + prompt biasing working well), Phase 2 simply doesn't trigger — that's a success outcome, not a stalled plan.
- The flagged sessions themselves become the fine-tuning dataset's seed — pair each flag with its audio + corrected text when Phase 2 starts.
