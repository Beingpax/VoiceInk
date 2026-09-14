# Reapply Direct Typing onto latest VoiceInk

Playbook for an AI agent. Direct Typing lives on fork PR [#701](https://github.com/Beingpax/VoiceInk/pull/701) until upstream (`Beingpax/VoiceInk`) merges it.

**Hard gate:** re-apply Direct Typing **only** if it is **not** already in the current upstream `main`. If it is merged, stop. Do not reset the feature branch, do not copy paste files, do not rebuild for this feature, do not force-push #701.

Last verified: VoiceInk **2.13** (`origin/main` `832d212`), Direct Typing rebased from commit `80e2983`. Build used Xcode 27 beta (`Xcode-beta.app`) plus Metal toolchain `27A5218h`.

Do **not** add `Co-authored-by: Cursor` (or any Cursor trailer) to commits. If `git commit` injects one, write the commit with `git commit-tree` instead.

## 1. Check whether Direct Typing is already upstream (mandatory)

Do this **before** any reset or patch. Fetch current upstream, then prove the feature is missing.

```bash
git fetch origin main
git grep -n 'directTyping\|case directTyping' origin/main -- '*.swift'
# 2.13+ path (sources were reorganized off VoiceInk/Paste/):
git show origin/main:VoiceInk/Infrastructure/SystemIntegration/Paste/PasteMethod.swift
# pre-2.13 path, if the file still lives there:
git show origin/main:VoiceInk/Paste/PasteMethod.swift
```

Also check the PR, in case GitHub merged it under a different branch name:

```bash
gh api repos/Beingpax/VoiceInk/pulls/701 --jq '{state, merged, merged_at, title}'
```

**Stop immediately** (report status; no further steps) if any of these is true:

- `PasteMethod` on `origin/main` already has `case directTyping`
- `git grep` on `origin/main` finds `directTyping` in Swift sources
- PR #701 is `MERGED` (or another upstream PR merged the same feature)

A closed-but-unmerged #701 is **not** a reason to skip: the code may still be absent from `main`. Trust `PasteMethod.swift` on `origin/main` over PR metadata.

**Continue only if** upstream `PasteMethod` is still just `standard` / `appleScript` (no `directTyping`). Then record:

- `origin/main` SHA and marketing version (`MARKETING_VERSION` in the Xcode project, or `appcast.xml`).
- Whether paste sources changed since the last Direct Typing commit (`VoiceInk/Paste/` or `VoiceInk/Infrastructure/SystemIntegration/Paste/`).

Typical remotes:

- `origin` / `upstream` → `https://github.com/Beingpax/VoiceInk.git`
- `fork` → `https://github.com/marib00/VoiceInk.git`
- Branch: `feature/paste-method-remote-desktop`

## 2. Snapshot the last known-good implementation, then reset

Skip this section unless section 1 confirmed Direct Typing is **absent** from current `origin/main`.

From the current Direct Typing branch (or the last DT commit). After 2.13 the paste files live under `Infrastructure/SystemIntegration/Paste/`; older DT commits still use `VoiceInk/Paste/`.

```bash
mkdir -p /tmp/dt-reapply
if git cat-file -e HEAD:VoiceInk/Infrastructure/SystemIntegration/Paste/CursorPaster.swift 2>/dev/null; then
  git show HEAD:VoiceInk/Infrastructure/SystemIntegration/Paste/CursorPaster.swift > /tmp/dt-reapply/CursorPaster.swift
  git show HEAD:VoiceInk/Infrastructure/SystemIntegration/Paste/PasteMethod.swift > /tmp/dt-reapply/PasteMethod.swift
else
  git show HEAD:VoiceInk/Paste/CursorPaster.swift > /tmp/dt-reapply/CursorPaster.swift
  git show HEAD:VoiceInk/Paste/PasteMethod.swift > /tmp/dt-reapply/PasteMethod.swift
fi
```

Stash or discard unrelated local changes. Do **not** re-bundle unrelated fixes (menu bar, etc.).

```bash
git checkout feature/paste-method-remote-desktop
git reset --hard origin/main
```

## 3. Re-apply the feature

Only after section 1 confirmed the feature is **not** on current upstream `main`.

Paste / settings / backup paths (2.13+):

- `VoiceInk/Infrastructure/SystemIntegration/Paste/{PasteMethod,CursorPaster}.swift`
- `VoiceInk/Features/Settings/Views/SettingsView.swift`
- `VoiceInk/Features/Settings/Backup/{BackupTypes,BackupImporter,ImportExportService}.swift`
- `VoiceInk/App/Configuration/AppDefaults.swift` (already calls `PasteMethod.migrateLegacyUserDefaultIfNeeded()`)

Pre-2.13 these lived under `VoiceInk/Paste/`, `VoiceInk/Views/Settings/`, and `VoiceInk/Services/`.

### Paste core

If `git diff <last-dt-base> origin/main --` the paste directory is empty **and** the destination path still matches the snapshot, copy the snapshots over. On 2.13+ the paste directory moved, so **port by hand** (do not `cp` a pre-2.13 snapshot onto the new tree).

Required behavior:

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
rg -n 'PowerModeManager|ModeManager|currentActiveConfiguration' \
  VoiceInk/Infrastructure/SystemIntegration/Paste/CursorPaster.swift \
  VoiceInk/Features/Modes/State/ModeConfig.swift
```

### Settings

In `VoiceInk/Features/Settings/Views/SettingsView.swift` paste picker:

- InfoTip: append “Direct Typing types character by character — use this when dictating into a remote desktop or virtual machine.”
- `onChange` must use `PasteMethod.resolve(newValue)`, not `PasteMethod(rawValue:)`.

Leave unrelated settings (Launch at Login, updates, export `Task { }`) untouched.

### Backup

`GeneralBackup` in `VoiceInk/Features/Settings/Backup/BackupTypes.swift`:

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

Copy the app yourself (direct `xcodebuild` does not). Debug builds use `PRODUCT_NAME = "VoiceInk Dev"`:

```bash
ditto ".local-build/Build/Products/Debug/VoiceInk Dev.app" "$HOME/Downloads/VoiceInk Dev.app"
xattr -cr "$HOME/Downloads/VoiceInk Dev.app"
```

Success: `BUILD SUCCEEDED`. App paths:

- `.local-build/Build/Products/Debug/VoiceInk Dev.app` (Debug)
- `~/Downloads/VoiceInk Dev.app` (after `ditto`)

### Build errors seen on 2.11+ (handle in this order)

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
  VoiceInk/Infrastructure/SystemIntegration/Paste/CursorPaster.swift \
  VoiceInk/Infrastructure/SystemIntegration/Paste/PasteMethod.swift \
  VoiceInk/Features/Settings/Backup/BackupImporter.swift \
  VoiceInk/Features/Settings/Backup/BackupTypes.swift \
  VoiceInk/Features/Settings/Backup/ImportExportService.swift \
  VoiceInk/Features/Settings/Views/SettingsView.swift \
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
| `PasteMethod.swift` missing at `VoiceInk/Paste/` | 2.13 source reorganization | Use `VoiceInk/Infrastructure/SystemIntegration/Paste/` and port by hand |
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
| Re-applied DT though it is already on main | Skipped the upstream gate | Stop if `PasteMethod` on `origin/main` has `directTyping` |

## Out of scope

- Second paste method named “Direct Typing (Remote Desktop)”.
- Menu-bar / activation-policy fixes.
- Changing Default or AppleScript paste behavior.
