# 0003. Telemetry via PostHog Cloud

## Status

Decided

## Context

We need a quantitative signal for "is this working" (see ADR context in CONTEXT.md's Flag event definition), not a gut-feel. Two real options were evaluated:

- **OpenTelemetry** — vendor-neutral, but `opentelemetry-swift` has no autocapture (fully manual instrumentation), and needs a separate backend (SigNoz/Grafana) plus hand-built dashboards to be usable by a non-engineer. Estimated ~4–6 days end to end.
- **PostHog** — native Swift/macOS SDK with autocapture and custom events; dashboard is built for non-engineers out of the box. Estimated ~1.5–3 days.

Within PostHog, self-hosted (Docker, own infra, consistent with VoiceInk's "nothing leaves the device" privacy pitch) vs PostHog Cloud (fastest, zero infra) was a further fork.

VoiceInk's own `SessionMetric` model already defines most of the event schema we need (word count, audio duration, model used, transcription duration, speed factor, active mode, enhancement duration/tokens) — mirrored into whichever telemetry backend, plus the flag event this ADR's context depends on, since stock VoiceInk has no failure/correction signal today.

## Decision

PostHog Cloud, not self-hosted. Chosen for speed over the self-hosted privacy alignment.

**Explicit trade-off**: structured metrics (word count, duration, model, mode, flag events) leave the device and reach PostHog's servers. Audio and transcript text never do — only the metadata fields above. This is a conscious exception to VoiceInk's otherwise fully local processing, made for setup speed, not because the privacy concern doesn't matter.

## Consequences

- Fast to stand up — no Docker/infra to maintain.
- If the privacy trade-off becomes uncomfortable later, migrating self-hosted PostHog is a backend swap, not a re-instrumentation — the event schema doesn't change, only where it's sent.
- Solo scope (ADR-0005) means the exposure is limited to one person's usage metadata, not aggregated data from multiple people.
