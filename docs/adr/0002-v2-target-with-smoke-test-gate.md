# 0002. Target v2.0, gated by a one-day smoke test, fallback to v1.79

## Status

Decided

## Context

VoiceInk 2.0 shipped 2026-07-16, two days before this decision, after a month of betas. Known issues at the time: #735 (global shortcut unreliable on macOS 26, 17 comments — the most-discussed open issue), #827 (lost custom modes on upgrade — an upgrade-path bug, shouldn't affect a clean source build), #686/#687 (short phrases producing no output / intermittent truncation). A batch of post-launch regressions were triaged and closed the day after release, suggesting active maintenance but a still-settling codebase.

v1.79 is the last pre-2.0 stable tag — slower-moving, lower regression risk, but without whatever 2.0 added.

## Decision

Build v2.0 first. Run it for one real work day against this bar:

- Global hotkey fires reliably every time (directly tests #735 against our actual macOS version)
- Power Mode auto-switches correctly across 3 apps in daily use
- Zero crashes or hangs over the day

Any failure on that bar → rebuild against v1.79 instead.

## Consequences

- We don't block on a multi-day soak test or wait for upstream to fully stabilize 2.0 — one day is enough signal given the bar is specific and falsifiable.
- If we degrade to v1.79, we lose whatever 2.0-only features exist until upstream stabilizes further; re-attempt the smoke test against a later 2.0.x patch when one ships.
- This ADR's bar is the source of truth for "did the smoke test pass" — don't relitigate the criteria mid-test.
