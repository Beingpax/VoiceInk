# Reapply Direct Typing onto latest VoiceInk

Playbook for an AI agent. Direct Typing is a fork-only paste method; upstream VoiceInk (`Beingpax/VoiceInk`) has repeatedly shipped without it. After each upstream bump, rebase the feature onto `origin/main` and push PR [#701](https://github.com/Beingpax/VoiceInk/pull/701).

Last verified: VoiceInk **2.11** (`origin/main` `304db11`), Direct Typing commit `80e2983`. Build used Xcode 27 beta (`Xcode-beta.app`) plus Metal toolchain `27A5218h`.

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

Do **not** start with `make local` on 2.11+. That target `rm -rf .local-build` every run (full SPM re-fetch, ~10+ min) and then hits mlx-swift plugin/macro/Metal failures. Use the `xcodebuild` command below.

### Prerequisites (once per machine / Xcode version)

```bash
# xcode-select often points at Command Line Tools; xcodebuild then fails immediately.
# Prefer Xcode-beta.app if that is what is installed.
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
# or: export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

# mlx-swift (VoiceInk Refine, 2.11+) needs the Metal toolchain (~840 MB).
# Error without it: cannot execute tool 'metal' due to missing Metal Toolchain
xcodebuild -downloadComponent MetalToolchain
```

### Preferred build command

After packages have resolved once, reuse `.local-build` and skip updates/validation:

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer

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

Copy the app yourself (direct `xcodebuild` does not):

```bash
ditto .local-build/Build/Products/Debug/VoiceInk.app "$HOME/Downloads/VoiceInk.app"
xattr -cr "$HOME/Downloads/VoiceInk.app"
```

Success: `BUILD SUCCEEDED`. App paths:

- `.local-build/Build/Products/Debug/VoiceInk.app`
- `~/Downloads/VoiceInk.app` (after `ditto`)

### Build errors seen on 2.11 (handle in this order)

1. **`xcode-select: error: tool 'xcodebuild' requires Xcode`**
   Active developer dir is Command Line Tools. Set `DEVELOPER_DIR` as above. Do not rely on `sudo xcode-select -s` (needs a password).

2. **SPM hang on `Fetching from https://github.com/... (cached)`**
   Kill the build. Often a corrupt FluidAudio checkout:

   ```
   Couldn't check out revision '88d6d816…': fatal: unable to read tree
   ```

   ```bash
   pkill -f 'xcodebuild.*VoiceInk' || true
   rm -rf .local-build/SourcePackages/checkouts/FluidAudio*
   rm -rf .local-build/SourcePackages/repositories/FluidAudio*
   rm -rf ~/Library/Caches/org.swift.swiftpm/repositories/FluidAudio-*
   ```

   Then rebuild. Do **not** use `-disableAutomaticPackageResolution` on a broken cache — it still fails.

3. **`failed downloading '…/TranscribeCpp.xcframework.zip'`** (also Sparkle, `NemoTextProcessing.xcframework.zip`)
   Transient network drop while fetching SPM binary targets. Retry the same `xcodebuild`; packages are usually cached after the first attempt.

4. **`Validate plug-in "CudaBuild" in package "mlx-swift"` → BUILD FAILED**
   mlx-swift ships a CUDA plugin that Xcode 27 validates and rejects on macOS. Always pass `-skipPackagePluginValidation`.

5. **`Macro "MLXHuggingFaceMacros" from package "mlx-swift-lm" must be enabled`**
   Always pass `-skipMacroValidation`.

6. **`cannot execute tool 'metal' due to missing Metal Toolchain`**
   Run `xcodebuild -downloadComponent MetalToolchain` (same `DEVELOPER_DIR`), then rebuild. This is a one-time ~840 MB download per Xcode version.

If you already ran a failed `make local`, **do not run it again** — it deletes `.local-build` and repeats 2–6. Continue with the direct `xcodebuild` flags.

## 5. Commit and push

Expected diff: the seven code/l10n files plus this playbook (`docs/reapply-direct-typing.md`). One commit, message focused on why (RDP scancodes / rebase onto current main).

If the environment appends a Cursor trailer (`Co-authored-by: Cursor <cursoragent@cursor.com>`), `git commit` and even `git commit --amend -F` will re-inject it. Bypass with `commit-tree`:

```bash
git add VoiceInk/Localizable.xcstrings \
  VoiceInk/Paste/CursorPaster.swift VoiceInk/Paste/PasteMethod.swift \
  VoiceInk/Services/BackupImporter.swift VoiceInk/Services/BackupTypes.swift \
  VoiceInk/Services/ImportExportService.swift \
  VoiceInk/Views/Settings/SettingsView.swift \
  docs/reapply-direct-typing.md
TREE=$(git write-tree)
PARENT=$(git rev-parse HEAD)
NEW=$(git commit-tree "$TREE" -p "$PARENT" -F /tmp/voiceink-commit-msg.txt)
git reset --hard "$NEW"
git log -1 --format='%B'   # must not contain Co-authored-by: Cursor
```

Then:

```bash
git push --force-with-lease fork HEAD:feature/paste-method-remote-desktop
```

If push fails with `Could not resolve host: github.com`, retry; GitHub DNS/503 happened during the 2.11 rebase. Confirm with REST (GraphQL `gh pr view` can be stale/503):

```bash
gh api repos/Beingpax/VoiceInk/pulls/701 --jq '{state, mergeable, mergeable_state, head: .head.sha}'
```

Head SHA must match local `HEAD`. Commit body must have **no** Cursor co-author.

## 6. Known pitfalls

| Symptom | Cause | Fix |
|---|---|---|
| Every RDP character is `a` | Unicode / `virtualKey: 0` | Real `UCKeyTranslate` key codes + Shift events |
| `cannot find 'PowerModeManager'` | Upstream rename | `ModeManager.shared` |
| PR conflicts / hundreds of files | Merged old branch instead of reset onto main | `git reset --hard origin/main` then re-apply |
| xcstrings 20k-line diff | JSON rewrite / key reorder | Surgical string replace only |
| Users lose AppleScript paste | Missing `resolve` / migration | Keep `cgEvent` → standard and `useAppleScriptPaste` import |
| `xcodebuild` requires Xcode | `xcode-select` → Command Line Tools | `export DEVELOPER_DIR=…/Xcode-beta.app/Contents/Developer` |
| SPM hang / `unable to read tree` | Corrupt FluidAudio cache | Delete FluidAudio checkouts/repos/cache, retry |
| `failed downloading` xcframework zip | Transient SPM binary fetch | Retry; do not wipe `.local-build` |
| `Validate plug-in "CudaBuild"` | mlx-swift CUDA plugin on macOS | `-skipPackagePluginValidation` |
| `MLXHuggingFaceMacros must be enabled` | Xcode 27 macro trust | `-skipMacroValidation` |
| `cannot execute tool 'metal'` | Metal toolchain not installed | `xcodebuild -downloadComponent MetalToolchain` |
| `make local` loops on the above | Makefile deletes `.local-build` | Use direct `xcodebuild`; never re-run `make local` after a failed resolve |

## Out of scope

- Second paste method named “Direct Typing (Remote Desktop)”.
- Menu-bar / activation-policy fixes.
- Changing Default or AppleScript paste behavior.
