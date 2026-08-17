# Reapply Direct Typing onto latest VoiceInk

Playbook for an AI agent. Direct Typing is a fork-only paste method; upstream VoiceInk (`Beingpax/VoiceInk`) has repeatedly shipped without it. After each upstream bump, rebase the feature onto `origin/main` and push PR [#701](https://github.com/Beingpax/VoiceInk/pull/701).

Do **not** add `Co-authored-by: Cursor` (or any Cursor trailer) to commits. If `git commit` injects one, write the commit with `git commit-tree` instead.

## 1. Check whether work is needed

```bash
git fetch origin main
git grep -n 'directTyping\|Direct Typing' origin/main -- '*.swift'
```

- Hits on `origin/main` → already merged; stop.
- No hits → continue.

Record:

- `origin/main` SHA and marketing version (`MARKETING_VERSION` in the Xcode project, or `appcast.xml`).
- Whether `VoiceInk/Paste/` changed since the last Direct Typing commit.

Typical remotes:

- `origin` / `upstream` → `https://github.com/Beingpax/VoiceInk.git`
- `fork` → `https://github.com/marib00/VoiceInk.git`
- Branch: `feature/paste-method-remote-desktop`

## 2. Snapshot the last known-good implementation, then reset

From the current Direct Typing branch (or the last DT commit):

```bash
mkdir -p /tmp/dt-reapply
git show HEAD:VoiceInk/Paste/CursorPaster.swift > /tmp/dt-reapply/CursorPaster.swift
git show HEAD:VoiceInk/Paste/PasteMethod.swift > /tmp/dt-reapply/PasteMethod.swift
```

Stash or discard unrelated local changes. Do **not** re-bundle unrelated fixes (menu bar, etc.).

```bash
git checkout feature/paste-method-remote-desktop
git reset --hard origin/main
```

## 3. Re-apply the feature

### Paste core

If `git diff <last-dt-base> origin/main -- VoiceInk/Paste` is empty, copy the snapshots over:

```bash
cp /tmp/dt-reapply/PasteMethod.swift VoiceInk/Paste/PasteMethod.swift
cp /tmp/dt-reapply/CursorPaster.swift VoiceInk/Paste/CursorPaster.swift
```

If `VoiceInk/Paste/` changed, port by hand. Required behavior:

1. `PasteMethod.directTyping = "directTyping"`.
2. Display name: `String(localized: "Direct Typing")` — **not** “(Remote Desktop)”. Remote-desktop context lives in the InfoTip only.
3. `PasteMethod.resolve(_:)` maps legacy `"cgEvent"` → `.standard`.
4. `startPasteAtCursor` must branch **before** clipboard paste:

```swift
if PasteMethod.current() == .directTyping {
    return await typeTextDirectly(text)
}
return await performPasteSession(text)
```

5. `typeTextDirectly` must:
   - Require accessibility (`AXIsProcessTrusted`).
   - Wait `prePasteDelay` (focus settle).
   - Build a layout map with `UCKeyTranslate` (unmodified + Shift only; **no Option/AltGr**).
   - Post **real** key codes + real Shift key down/up (RDP ignores Unicode / `virtualKey: 0` and types `a`).
   - Special-case `\n`/`\r` → Return, `\t` → Tab.
   - Use Shift+Return for embedded newlines **only** when `ModeManager.shared.currentActiveConfiguration?.autoSendKey == .enter`.
   - Fall back to Unicode injection for unmapped characters (emoji, dead keys).
   - Sleep ~5ms between keys.

Never call `PowerModeManager` — it was renamed to `ModeManager`. Confirm:

```bash
rg -n 'PowerModeManager|ModeManager|currentActiveConfiguration' VoiceInk/Paste/CursorPaster.swift VoiceInk/Modes/ModeConfig.swift
```

### Settings

In `VoiceInk/Views/Settings/SettingsView.swift` paste picker:

- InfoTip: append “Direct Typing types character by character — use this when dictating into a remote desktop or virtual machine.”
- `onChange` must use `PasteMethod.resolve(newValue)`, not `PasteMethod(rawValue:)`.

Leave unrelated settings (Launch at Login, updates, export `Task { }`) untouched.

### Backup

`GeneralBackup` in `VoiceInk/Services/BackupTypes.swift`:

```swift
let useAppleScriptPaste: Bool?  // legacy — kept for backward-compat import
let pasteMethod: String?
```

`BackupImporter`: after clipboard delay, resolve `pasteMethod`, else migrate `useAppleScriptPaste`.

`ImportExportService`: export `pasteMethod: PasteMethod.current().rawValue` and `useAppleScriptPaste: nil`. `exportSettings` may be `async`; only add the two fields to the `GeneralBackup(...)` call.

`AppDefaults.registerDefaults()` already calls `PasteMethod.migrateLegacyUserDefaultIfNeeded()` — keep that.

### Localization

Surgical edits only. Never rewrite `Localizable.xcstrings`.

- Add key `"Direct Typing"` (`de`: Direktes Tippen, `zh-Hans`: 直接键入). Insert after the `"AppleScript"` entry if that is still the neighbor.
- Replace the paste-method InfoTip key with the longer string; keep existing `de` / `zh-Hans` translations and extend them. If new locales appear, add them.

Validate JSON after editing.

## 4. Build

From 2.11 onward, VoiceInk pulls mlx-swift (Refine). A plain `make local` can fail on:

- SPM binary downloads dropping (`TranscribeCpp.xcframework.zip`, Sparkle, NemoTextProcessing) — retry.
- `Validate plug-in "CudaBuild"` in mlx-swift — skip plugin validation.
- Macros from `mlx-swift-lm` not enabled — skip macro validation.
- Missing Metal toolchain — `xcodebuild -downloadComponent MetalToolchain`.

`make local` also `rm -rf .local-build` every run, which forces a full SPM re-fetch. Prefer a direct `xcodebuild` after the first resolve:

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer   # or Xcode.app

# once per machine / Xcode version
xcodebuild -downloadComponent MetalToolchain

xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Debug \
  -derivedDataPath "$PWD/.local-build" \
  -xcconfig LocalBuild.xcconfig \
  -skipPackageUpdates \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES \
  DEVELOPMENT_TEAM="" \
  CODE_SIGN_ENTITLEMENTS="$PWD/VoiceInk/VoiceInk.local.entitlements" \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) LOCAL_BUILD' \
  build
```

If `xcode-select` points at Command Line Tools, `DEVELOPER_DIR` is required.

If SPM hangs or fails with a missing FluidAudio revision:

```bash
rm -rf .local-build/SourcePackages/checkouts/FluidAudio*
rm -rf .local-build/SourcePackages/repositories/FluidAudio*
rm -rf ~/Library/Caches/org.swift.swiftpm/repositories/FluidAudio-*
```

then rebuild.

Success: `BUILD SUCCEEDED`. App path:

`.local-build/Build/Products/Debug/VoiceInk.app`

`make local` also copies to `~/Downloads/VoiceInk.app`. A direct `xcodebuild` does not.

## 5. Commit and push

Expected diff: the seven files above (~240 insertions). One commit, message focused on why (RDP scancodes / rebase onto current main).

If the environment appends a Cursor trailer:

```bash
git add <the seven files>
TREE=$(git write-tree)
PARENT=$(git rev-parse HEAD)
NEW=$(git commit-tree "$TREE" -p "$PARENT" -F /tmp/voiceink-commit-msg.txt)
git reset --hard "$NEW"
```

Then:

```bash
git push --force-with-lease fork HEAD:feature/paste-method-remote-desktop
```

Confirm PR 701 head SHA matches, mergeable, and the commit body has **no** Cursor co-author.

## 6. Known pitfalls

| Symptom | Cause | Fix |
|---|---|---|
| Every RDP character is `a` | Unicode / `virtualKey: 0` | Real `UCKeyTranslate` key codes + Shift events |
| `cannot find 'PowerModeManager'` | Upstream rename | `ModeManager.shared` |
| PR conflicts / hundreds of files | Merged old branch instead of reset onto main | `git reset --hard origin/main` then re-apply |
| xcstrings 20k-line diff | JSON rewrite / key reorder | Surgical string replace only |
| Users lose AppleScript paste | Missing `resolve` / migration | Keep `cgEvent` → standard and `useAppleScriptPaste` import |

## Out of scope

- Second paste method named “Direct Typing (Remote Desktop)”.
- Menu-bar / activation-policy fixes.
- Changing Default or AppleScript paste behavior.
