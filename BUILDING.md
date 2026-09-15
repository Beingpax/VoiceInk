# Building VoiceInk

## Requirements

- macOS 14.4 or later
- Xcode with Command Line Tools
- Git

## Local Build

```bash
git clone https://github.com/Beingpax/VoiceInk.git
cd VoiceInk
make local
open ~/Downloads/VoiceInk.app
```

`make local` prepares `whisper.xcframework` in `~/VoiceInk-Dependencies`, builds Release in `.local-build`, and copies `VoiceInk.app` to `~/Downloads`.

It uses `LocalBuild.xcconfig`, `VoiceInk.local.entitlements`, and the `LOCAL_BUILD` Swift flag. Without an override, it uses the only available Apple Development identity or falls back to ad-hoc signing when none or multiple are found.

Choose an identity explicitly:

```bash
make local LOCAL_CODESIGN_IDENTITY="<SHA or name>"
```

Force ad-hoc signing:

```bash
make local LOCAL_CODESIGN_IDENTITY=-
```

Local builds do not include iCloud dictionary sync or automatic updates. Ad-hoc builds may require macOS permissions again after rebuilding.

On macOS 26 or later, a local build can use Apple Intelligence for enhancement from Model Library → Local. The on-device model is AFM 3 Core or AFM 3 Core Advanced; the Mac picks the variant (Advanced on M3 or later with at least 12 GB). Private Cloud Compute needs macOS 27 and Apple’s `com.apple.developer.private-cloud-compute` entitlement on a Developer ID or App Store build. Signing without that entitlement is not enough; ad-hoc local builds hide PCC.

## Other Commands

- `make check` — verify required tools
- `make whisper` — prepare `whisper.xcframework`
- `make build` — build the standard Debug configuration
- `make dev` — build and launch `VoiceInk Dev.app`
- `make run` — launch `~/Downloads/VoiceInk.app`, or the first app found in DerivedData
- `make release` — create the signed release package
- `make release-setup` — configure release notarization credentials
- `make clean` — remove `~/VoiceInk-Dependencies`
- `make help` — list all commands

## Build with Xcode

```bash
make setup
open VoiceInk.xcodeproj
```

Select the `VoiceInk` scheme. Run builds `VoiceInk Dev.app`; Archive uses Release. `LOCAL_BUILD` applies only through `make local`.

## Troubleshooting

- Run `make check` to verify the required tools.
- Run `make whisper` if the framework is missing.
- If several Apple Development identities exist, set `LOCAL_CODESIGN_IDENTITY` explicitly.
- `make local` on Xcode 26 can fail because VoiceInk Refine pulls `mlx-swift` 0.31.6, which requires Swift tools 6.3. Use an Xcode that includes Swift 6.3, or wait for a Refine pin that still builds on Xcode 26.
- For additional help, open a [GitHub issue](https://github.com/Beingpax/VoiceInk/issues).
