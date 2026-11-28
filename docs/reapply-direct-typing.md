# Keep the VoiceInk fork on latest upstream (left/right modifiers + remote desktop typing)

Playbook for an AI agent. The fork `marib00/VoiceInk` must always provide two things on top of `Beingpax/VoiceInk`:

1. **Remote desktop typing**: dictated text reaches RDP / VM windows as real key codes. Upstream ships this since **2.25** as the **Remote Desktop Typing** paste method (`PasteMethod.remoteTyping`, `RemoteTextTyper`). The fork no longer carries paste code.
2. **Left/right modifier shortcuts**: shortcuts can require a specific side (`Left ⌘ + Space`, `Left ⌃ + Right ⌥`, `Right ⌥ + Mouse 4`). Upstream only distinguishes sides for **single-modifier** shortcuts (`Right ⌘` alone). The fork carries one commit for the rest.

**Never push to upstream.** Do not `git push origin`, `git push upstream`, or write to `Beingpax/VoiceInk` in any way (no PRs, merges, review requests). Push **only** to `fork` (`marib00/VoiceInk`).

Do **not** add `Co-authored-by: Cursor` (or any Cursor trailer) to commits. If `git commit` injects one, write the commit with `git commit-tree` (section 6).

Last verified: VoiceInk **2.27** (`origin/main` `b5d1be9`). Built Release with Xcode 27 beta (`Xcode-beta.app`, `27A5218g`, Swift 6.4) plus Metal toolchain `27A5218h`, using the two local dependency workarounds in section 5. Signed with the Apple Development identity and installed as `/Applications/VoiceInk.app` (previous build kept as `VoiceInk.prev.app`).

History: the fork carried its own "Direct Typing" (real key codes) through 2.21 (last commit `8c1fdd0`). Upstream 2.25 added both **Direct Typing** (Unicode events — types `a` in RDP) and **Remote Desktop Typing** (real key codes — the fork's old behavior). The raw value `directTyping` therefore changed meaning; see section 5.

Remotes and branch:

- `origin` / `upstream` → `https://github.com/Beingpax/VoiceInk.git` (**fetch only**)
- `fork` → `https://github.com/marib00/VoiceInk.git` (**only push target**)
- Branch: `feature/paste-method-remote-desktop` (historic name; now holds the left/right modifier commit)

## 1. Gates (mandatory, before any reset)

```bash
git fetch origin main
git fetch fork
git log --oneline -1 origin/main
git show origin/main:VoiceInk.xcodeproj/project.pbxproj | grep -m1 MARKETING_VERSION
```

### 1a. Remote desktop typing

```bash
git show origin/main:VoiceInk/Infrastructure/SystemIntegration/Paste/PasteMethod.swift
git show origin/main:VoiceInk/Infrastructure/SystemIntegration/Paste/RemoteTextTyper.swift | head -40
```

- `PasteMethod` has `case remoteTyping` and `RemoteTextTyper` posts real key codes with real Shift down/up → **nothing to do for paste**.
- `remoteTyping` is gone and nothing else posts real key codes → restore the fork implementation from `8c1fdd0` (appendix A). Do not open a PR upstream.

Requirements for any remote typing implementation (check upstream against these after big paste changes):

- Requires accessibility (`AXIsProcessTrusted`), waits `prePasteDelay` for focus, never touches the clipboard.
- Layout map via `UCKeyTranslate` (unmodified + Shift only; no Option/AltGr, no dead keys).
- Real key codes plus real Shift key down/up. RDP ignores Unicode payloads / `virtualKey: 0` and types `a`.
- `\n` → Return (Shift+Return when the effective Finish and Send key is Return), `\t` → Tab, ~5 ms between keys.

### 1b. Left/right modifiers

As of 2.27, upstream's `normalizedModifierFlags` keeps only `[.control, .option, .shift, .command, .function]`, so side bits never reach stored key, mouse, or chord shortcuts. Check whether upstream now stores sides for combinations:

```bash
git show origin/main:VoiceInk/Features/Shortcuts/Models/Shortcut.swift | \
  rg -n 'deviceDependentModifierMask|flagsByCapturingModifierSides|modifiersStillHeld|func normalizedModifierFlags' -A6
```

- Upstream already records and matches sides for key, mouse, and multi-modifier shortcuts (it has an equivalent of `flagsByCapturingModifierSides` / `modifiersStillHeld`) → drop the fork commit; run the checks in section 4 against upstream instead.
- Otherwise continue. Record the fork's left/right commit:

```bash
git log --oneline origin/main..fork/feature/paste-method-remote-desktop
LR=$(git log --format=%H -1 --grep='left and right modifier' fork/feature/paste-method-remote-desktop)
```

## 2. Back up, then reset

Never lose local work. Uncommitted changes go to a backup branch first (plumbing keeps the working tree and avoids trailers):

```bash
git status --short
export GIT_INDEX_FILE=/tmp/backup.idx
git read-tree HEAD && git add -A VoiceInk scripts docs
TREE=$(git write-tree); unset GIT_INDEX_FILE
printf 'WIP backup before rebasing onto upstream\n' > /tmp/backup-msg.txt
git branch "backup/$(date +%Y%m%d)" "$(git commit-tree "$TREE" -p HEAD -F /tmp/backup-msg.txt)"
git stash push -m "pre-rebase local changes"
```

Leave unrelated stashes alone. Then:

```bash
git checkout feature/paste-method-remote-desktop
git reset --hard origin/main
```

## 3. Re-apply left/right modifiers

```bash
git cherry-pick --no-commit "$LR"
# or, for uncommitted work: git diff > /tmp/lr.patch (before reset) and git apply --3way /tmp/lr.patch
```

Files: `VoiceInk/Features/Shortcuts/{Models/Shortcut.swift, Coordination/ShortcutMonitor.swift, State/ShortcutValidator.swift, Views/ShortcutRecorder.swift}`, `scripts/check-shortcut-sides.swift`, and this playbook. Conflicts are expected in `Shortcut.swift` whenever upstream touches shortcut matching.

### Required behavior

- **Storage**: `modifierFlagsRawValue` keeps generic flags plus `NX_DEVICE*` side bits (`IOKit.hidsystem`) for `.key`, `.mouseButton`, and generic `.modifierOnly` chords (`keyCode == UInt16.max`). Side bits without their generic flag are dropped (`sanitizedModifierFlags`).
- **Single-modifier shortcuts** (`.modifierOnly` with a concrete modifier key code) store generic flags only; the key code carries the side. A recorded `Right ⌘` must equal `Shortcut.rightCommand`.
- **Recording**: `ShortcutRecorder` captures sides with `Shortcut.flagsByCapturingModifierSides` for key down, mouse down, and the flags-changed peak.
- **Matching**: generic flags must match exactly. If the stored shortcut has side bits, the event's side bits must equal them exactly; without stored sides either side matches (old shortcuts keep working).
- **Held / release**: `modifiersStillHeld(in:)` (generic superset + required sides).
- **Conflicts**: same kind, key, and generic flags, and overlapping sides (side-agnostic overlaps both). `Left ⌘ K` and `Right ⌘ K` can coexist.
- **Display**: `Left ⌘ + Space`, `Left ⌃ + Right ⌥`; unsided shortcuts unchanged (`⌘ + Space`).
- **Keep upstream's single-modifier logic**: `matchesModifierEvent` / `shouldReleaseModifierEvent` for concrete modifier key codes keep `Shortcut.modifierKeyIsDown(keyCode, flags:)` and compare against `genericModifierFlags`.

### Call-site audit (most important step)

`normalizedModifierFlags` strips side bits; `shortcut.modifierFlags` keeps them. Any upstream code that compares the two silently stops matching sided shortcuts. After applying, list every comparison:

```bash
rg -n 'normalizedModifierFlags|\.modifierFlags\b|isSuperset' VoiceInk/Features/Shortcuts
```

Rewrite each comparison against a stored shortcut:

| Upstream pattern | Replace with |
|---|---|
| `normalizedModifierFlags(x, …).isSuperset(of: shortcut.modifierFlags)` | `shortcut.modifiersStillHeld(in: x)` |
| `normalizedModifierFlags(x, …) == shortcut.modifierFlags` | `Shortcut.flagsByCapturingModifierSides` + side-aware compare (as `matchesKeyEvent`) or `== shortcut.genericModifierFlags` for single-modifier shortcuts |
| diagnostics `flags != state.shortcut.modifierFlags` | `flags != state.shortcut.genericModifierFlags` |

Sites rewritten as of 2.27: `Shortcut.isCurrentlyPressed` (missed-release recovery via `RecordingShortcutManager`), `ShortcutMonitor.matchesShortcut` (cancel/escape pre-check), two `.flagsChanged` transitions in `ShortcutMonitor` (key and mouse shortcuts), and the modifier-mismatch diagnostic. `recordingShortcut.modifierFlags.subtracting(...)` is fine (stray side bits are dropped by `sanitizedModifierFlags`). Recorder checks like `modifiers.isEmpty` are fine.

## 4. Verify the logic

Fast check of `Shortcut.swift` alone (seconds, no app build):

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
xcrun swiftc -swift-version 5 -parse-as-library -o /tmp/check-shortcut-sides \
  scripts/check-shortcut-sides.swift VoiceInk/Features/Shortcuts/Models/Shortcut.swift \
  && /tmp/check-shortcut-sides
```

Must print `ALL PASSED`. If upstream adds another app type to `Shortcut.swift`, stub it in the script. Add a case to the script for every new behavior.

## 5. Build and install

Do **not** use `make local`: it `rm -rf .local-build` every run (full SPM re-fetch) and lacks the flags below. Use `xcodebuild` directly.

### Prerequisites (once per machine / Xcode version)

```bash
# xcode-select often points at Command Line Tools; xcodebuild then fails immediately.
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
# mlx-swift (VoiceInk Refine, 2.11+) needs the Metal toolchain (~840 MB).
xcodebuild -downloadComponent MetalToolchain
# Apple Development identity for stable signing (keeps Accessibility/Microphone grants across rebuilds):
security find-identity -v -p codesigning
```

### Build (Release, same bundle ID as the installed app)

The installed app is a **Release** build (`com.prakashjoshipax.VoiceInk`), so settings carry over. Debug builds use `com.prakashjoshipax.VoiceInk.dev` and start with empty settings.

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
IDENTITY=$(security find-identity -v -p codesigning | awk '/"Apple Development: / { print $2; exit }')
# No identity: use CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO (ad-hoc; permissions reset on every rebuild).

xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Release \
  -derivedDataPath "$PWD/.local-build" \
  -xcconfig LocalBuild.xcconfig \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  CODE_SIGN_IDENTITY="$IDENTITY" CODE_SIGNING_REQUIRED=YES CODE_SIGNING_ALLOWED=YES \
  DEVELOPMENT_TEAM="" \
  CODE_SIGN_ENTITLEMENTS="$PWD/VoiceInk/VoiceInk.local.entitlements" \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) LOCAL_BUILD' \
  build
```

Add `-skipPackageUpdates` only when `Package.resolved` did not change since the last successful build (always add it once the Xcode-beta workarounds below are in place, so the patched checkout is not replaced).

### Xcode 27 beta (`27A5218g`) workarounds — local only, never commit

Upstream 2.27 dependencies target a newer macOS 27 SDK / Swift 6.4 than this beta. The real fix is installing a current Xcode 27; until then, both of these are needed and neither touches tracked files:

1. **swift-collections 1.7.5** fails (`'BorrowingIteratorProtocol' requires -enable-experimental-feature BorrowingSequence`, then `maxCount:` vs `maximumCount:`). The flag alone does not help. Pin 1.6.0 (all dependents accept ≥1.1.0) for the build, then restore the file:
   ```bash
   R=VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
   # in the swift-collections pin: revision a0cb0954ecb21e4e31b0070e6ed5674e8556685a, version 1.6.0
   # ... build ...
   git checkout -- "$R"
   ```
2. **FluidAudio** (`main`, LFM3-Audio since `4e2985f`) fails: `value of type 'NDArray.MutableRawView' has no member 'withUnsafeMutableBytes'`. VoiceInk does not use LFM3, but the file compiles whenever CoreAI exists. Do **not** pin FluidAudio back (that drops dozens of ASR fixes). Patch `zero(_:)` in the checkout to the beta API (`mutableBytes`):
   ```bash
   F=.local-build/SourcePackages/checkouts/FluidAudio/Sources/FluidAudio/ASR/LFM3Audio/LFM3AudioCoreAIBackbone.swift
   chmod u+w "$F"
   # replace the body of `array.mutableRawView().withUnsafeMutableBytes { … }` with:
   #     var view = array.mutableRawView()
   #     var bytes = view.mutableBytes
   #     bytes.withUnsafeMutableBytes { buffer in
   #         if let base = buffer.baseAddress { _ = memset(base, 0, buffer.count) }
   #     }
   ```
   The patch is lost when SPM re-checks out FluidAudio (new pin, deleted `.local-build`); re-apply it.

### Install

```bash
osascript -e 'quit app "VoiceInk"'; sleep 2
[ -d /Applications/VoiceInk.prev.app ] && mv /Applications/VoiceInk.prev.app ~/.Trash/"VoiceInk.prev $(date +%s).app"
mv /Applications/VoiceInk.app /Applications/VoiceInk.prev.app
ditto .local-build/Build/Products/Release/VoiceInk.app /Applications/VoiceInk.app
xattr -cr /Applications/VoiceInk.app
```

**Paste method migration** (only needed once per machine that ran the fork ≤2.21): the fork's old `directTyping` value now selects upstream's Unicode Direct Typing, which types `a` in RDP. Switch it before launching:

```bash
[ "$(defaults read com.prakashjoshipax.VoiceInk pasteMethod 2>/dev/null)" = directTyping ] \
  && defaults write com.prakashjoshipax.VoiceInk pasteMethod remoteTyping
open /Applications/VoiceInk.app
```

Backups exported by the fork ≤2.21 also contain `"pasteMethod": "directTyping"`; after importing one, re-select **Remote Desktop Typing** in Settings.

If the signing identity changed (e.g. ad-hoc → Apple Development), macOS asks again for Accessibility (System Settings → Privacy & Security → Accessibility: remove the old VoiceInk entry, add the new app) and possibly Microphone / Screen Recording. Without Accessibility, shortcuts and typing do nothing.

### Manual smoke test

- Settings → Shortcuts: record `Left ⌘ + Space` (display shows `Left ⌘ + Space`). It fires with left ⌘ only. Record `Right ⌘ + Space` for another action; no conflict warning.
- Record a single `Right ⌘` shortcut; it still works and shows `Right ⌘`.
- Settings → Paste method = **Remote Desktop Typing**; dictate into an RDP/VM window: correct letters, capitals, punctuation, newlines.

### Build errors seen (handle in this order)

1. **`xcode-select: error: tool 'xcodebuild' requires Xcode`** — set `DEVELOPER_DIR` as above (no `sudo xcode-select`).
2. **`Couldn't check out revision …: fatal: unable to read tree`** for many packages — upstream bumped `Package.resolved` and `-skipPackageUpdates` blocks the fetch. Drop that flag. If a single package (often FluidAudio) stays corrupt:
   ```bash
   pkill -f 'xcodebuild.*VoiceInk' || true
   rm -rf .local-build/SourcePackages/checkouts/FluidAudio* .local-build/SourcePackages/repositories/FluidAudio*
   rm -rf ~/Library/Caches/org.swift.swiftpm/repositories/FluidAudio-*
   ```
3. **`failed downloading '…xcframework.zip'`** — transient; retry the same command.
4. **`BorrowingIteratorProtocol …`** in swift-collections or **`NDArray.MutableRawView` has no member …** in FluidAudio — Xcode 27 beta SDK too old; see the workarounds above.
5. **`Validate plug-in "CudaBuild"`** — always pass `-skipPackagePluginValidation`.
6. **`Macro "MLXHuggingFaceMacros" … must be enabled`** — always pass `-skipMacroValidation`.
7. **`cannot execute tool 'metal'`** — `xcodebuild -downloadComponent MetalToolchain`.

Run long builds in a foreground/background shell that outlives the tool call; a `( … ) &` subshell can be killed when the call returns, leaving a log with no result.

## 6. Commit and push (fork only)

One commit on top of `origin/main`: the four Shortcuts files, `scripts/check-shortcut-sides.swift`, and this playbook. Message focused on why.

```bash
git add VoiceInk/Features/Shortcuts scripts/check-shortcut-sides.swift docs/reapply-direct-typing.md
git status --short   # nothing else staged
TREE=$(git write-tree)
NEW=$(git commit-tree "$TREE" -p "$(git rev-parse HEAD)" -F /tmp/voiceink-commit-msg.txt)
git reset --hard "$NEW"
git log -1 --format='%B'   # must not contain Co-authored-by: Cursor
```

Push **only** to `fork`:

```bash
git remote -v   # origin = Beingpax (fetch); fork = marib00 (push)
git push --force-with-lease=feature/paste-method-remote-desktop:<previous fork SHA> \
  fork HEAD:feature/paste-method-remote-desktop
git ls-remote fork refs/heads/feature/paste-method-remote-desktop
git rev-parse HEAD   # must match
```

Optionally push backup branches to `fork` too. Never to `origin` / `upstream`.

## 7. Known pitfalls

| Symptom | Cause | Fix |
|---|---|---|
| Every RDP character is `a` | Unicode typing (`directTyping` since 2.25) | Paste method **Remote Desktop Typing** (`remoteTyping`); migrate defaults (section 5) |
| Sided shortcut never fires / never releases | Upstream call site compares `normalizedModifierFlags` (sides stripped) with `shortcut.modifierFlags` (sides kept) | Call-site audit (section 3) |
| `Right ⌘` default shortcut shows as changed | Single-modifier shortcut stored with side bits | Strip sides in `init` for concrete modifier key codes |
| Left ⌘ fires `Right ⌘` shortcut | Lost upstream `modifierKeyIsDown` check during conflict resolution | Keep it in `matchesModifierEvent` / `shouldReleaseModifierEvent` |
| Shortcuts / typing dead after install | Accessibility grant tied to old signature | Re-grant Accessibility; sign with Apple Development identity |
| Settings empty after install | Built Debug (`.dev` bundle ID) | Build Release |
| `unable to read tree` on many packages | `-skipPackageUpdates` with new pins | Drop the flag |
| `BorrowingIteratorProtocol requires …` | swift-collections 1.7.5 on Xcode 27 beta | Pin 1.6.0 for the build only |
| `NDArray.MutableRawView` has no member `withUnsafeMutableBytes` | FluidAudio LFM3 on Xcode 27 beta SDK | Patch `zero(_:)` in the checkout; or update Xcode |
| `make local` loops on errors | Makefile deletes `.local-build` | Direct `xcodebuild` |
| xcstrings 20k-line diff | JSON rewrite / key reorder | Surgical string edits only |
| Commits appeared on Beingpax/VoiceInk | Pushed to `origin` / `upstream` | Push **only** `fork` |

## Appendix A. Restoring the fork's remote typing (only if upstream drops `remoteTyping`)

Port by hand from `git show 8c1fdd0` (2.21 layout under `VoiceInk/Infrastructure/SystemIntegration/Paste/`): `PasteMethod` case + display name + `resolve(_:)` (legacy `cgEvent` → `.standard`), `CursorPaster.typeTextDirectly` (branch before clipboard paste, return `PasteOutcome`, call `AutoLearnService.shared.pasteDidFinish` when Auto Learn is on), Settings picker InfoTip + `PasteMethod.resolve` in `onChange`, backup `pasteMethod` field in `BackupTypes` / `BackupImporter` / `ImportExportService`, and `Localizable.xcstrings` keys (`de`, `fr`, `zh-Hans`; surgical edits, validate JSON). Use a raw value other than `directTyping` (upstream owns it). Meet the requirements in section 1a.

## Out of scope

- Pushing, merging, or opening PRs against `Beingpax/VoiceInk`.
- Menu-bar / activation-policy fixes.
- Changing Default, AppleScript, Direct Typing, or Remote Desktop Typing behavior when upstream already meets section 1a.
