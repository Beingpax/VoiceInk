# 0007. Disable Sparkle auto-update in local builds

## Status

Decided

## Context

The first smoke-test launch of our `make local` build got silently replaced by the official upstream-signed binary: Sparkle's `UpdaterViewModel` unconditionally called `SPUStandardUpdaterController(startingUpdater: true, ...)` and inherited `automaticallyChecksForUpdates = true` from `Info.plist`, with no `LOCAL_BUILD` guard — unlike the dictionary/CloudKit config a few lines above it in the same file, which does correctly branch on `LOCAL_BUILD`. Accepting the resulting prompt swapped `~/Downloads/VoiceInk.app`'s signature from ad-hoc (ours) to `TeamIdentifier=V6J6A3VWY2` (upstream's real signing identity) — silently undoing ADR-0001's whole point of owning the build.

## Decision

Guard Sparkle's updater startup with `#if LOCAL_BUILD` in `VoiceInk/VoiceInk.swift`'s `UpdaterViewModel.init()`: pass `startingUpdater: false` and explicitly set `automaticallyChecksForUpdates = false` for local builds, leaving upstream's real (signed, distributed) builds unaffected.

## Consequences

- Local builds no longer background-check or prompt for updates — safe to leave running without risk of another silent swap.
- The manual "Check for Updates…" menu item still exists in local builds but won't do anything useful since the updater never started; acceptable since no one should be triggering it deliberately on a local build.
- Quick verification anytime: `codesign -dv ~/Downloads/VoiceInk.app 2>&1 | grep TeamIdentifier` — `not set` means our build, `V6J6A3VWY2` means it got replaced by the official one again.
- This is a deliberate divergence from upstream `VoiceInk.swift` — expect this hunk to require manual re-application on future upstream syncs if upstream touches the same function.
