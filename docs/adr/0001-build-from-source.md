# 0001. Build VoiceInk from source rather than buying the compiled binary

## Status

Decided

## Context

VoiceInk is GPLv3, source available on GitHub. The compiled binary is sold for $39.99 one-time (not a subscription) to fund development; `BUILDING.md` documents a `make local` path that ad-hoc signs a working build with no Apple Developer account needed.

We also need to add our own telemetry hooks and, eventually, swap in a fine-tuned model — both require owning the build, not just running the shipped binary.

## Decision

Fork the repo (`aadhar-build/VoiceInk` off `Beingpax/VoiceInk`), build locally via `make local`. No license purchased.

## Consequences

- Zero cost, full control over the build and future modifications.
- We take on our own build maintenance (Xcode/Swift toolchain, whisper.cpp framework build) instead of getting automatic updates the paid binary provides.
- Upstream sync becomes our responsibility — see the fork's `upstream` remote and the sync cadence described in `docs/agents/issue-tracker.md`.
