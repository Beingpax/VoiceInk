# Context

This fork customizes [VoiceInk](https://github.com/Beingpax/VoiceInk) (upstream) into a private, system-wide dictation tool tuned for Indian English, for one user on one Mac. Two additions on top of stock VoiceInk: usage/quality telemetry, and a path to a personal Whisper fine-tune once there's enough data to justify it.

## Vocabulary

- **Flag event** — the one-keystroke "this came out wrong" action taken right after a bad dictation. The primary accuracy signal, logged to PostHog. Not a correction or a transcript diff — just a binary "this was wrong" marker, chosen over auto-detection to keep the interaction friction-free.
- **Smoke test** — the one-day acceptance check (ADR-0002) that decides whether the build stays on v2.0 or falls back to v1.79.
- **Phase 1** — Personal Dictionary + prompt biasing for accent/vocabulary, telemetry wired up, shipped rough into daily use. No fine-tuning yet.
- **Phase 2** — the LoRA fine-tune, gated by the trigger in ADR-0004. Not a fixed date — a condition.
- **Solo scope** — this build assumes one user, one device (ADR-0005). No `device_id`/`user_id` dimension in telemetry yet; add it if that assumption ever changes.

## Where decisions live

`docs/adr/` holds the why behind each decision above — read the relevant one before changing behavior it covers. Actionable phase-wise work is tracked as GitHub Issues on this fork (`aadhar-build/VoiceInk`); `upstream` (`Beingpax/VoiceInk`) is read-only except for occasional PRs contributed back.
