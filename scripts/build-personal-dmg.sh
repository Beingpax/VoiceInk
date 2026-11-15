#!/usr/bin/env bash
set -euo pipefail

# Builds a Developer ID-signed, notarized DMG for personal distribution.
# Requires a "Developer ID Application" certificate and an App Store Connect
# API key for notarytool. Notarization uploads the DMG to Apple; no public release is published.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TEAM_ID="${VOICEINK_TEAM_ID:-$(awk -F ' = ' '/^DEVELOPMENT_TEAM = / {print $2; exit}' "$REPO_ROOT/LocalBuild.xcconfig")}"
IDENTITY="${VOICEINK_DEVELOPER_IDENTITY:-Developer ID Application}"
NOTARY_KEY="${VOICEINK_NOTARY_KEY:-}"
NOTARY_KEY_ID="${VOICEINK_NOTARY_KEY_ID:-}"
NOTARY_ISSUER="${VOICEINK_NOTARY_ISSUER:-}"
OUTPUT_DIR="${VOICEINK_DMG_OUTPUT:-$HOME/Downloads/VoiceInk-dmg}"
NOTARY_PROFILE="${VOICEINK_NOTARY_PROFILE:-}"
SKIP_NOTARIZATION=0

usage() {
    cat <<'USAGE'
Usage: scripts/build-personal-dmg.sh [options]

Builds, signs with Developer ID, packages, and notarizes a DMG for personal use.

Options:
  --skip-notarization   Sign and package only (no Apple submission).
  --output <dir>        Output directory (default ~/Downloads/VoiceInk-dmg).
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-notarization) SKIP_NOTARIZATION=1; shift ;;
        --output) OUTPUT_DIR="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

cd "$REPO_ROOT"

if ! security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
    cat >&2 <<'MESSAGE'
error: "Developer ID Application" 証明書がありません。

Xcode → Settings → Accounts → チームを選ぶ → Manage Certificates → 「+」→
Developer ID Application で作成してから、もう一度実行してください。
MESSAGE
    exit 1
fi

if [[ "$SKIP_NOTARIZATION" -eq 0 && -z "$NOTARY_PROFILE" ]]; then
    : "${NOTARY_KEY:?Set VOICEINK_NOTARY_KEY or VOICEINK_NOTARY_PROFILE}"
    : "${NOTARY_KEY_ID:?Set VOICEINK_NOTARY_KEY_ID}"
    : "${NOTARY_ISSUER:?Set VOICEINK_NOTARY_ISSUER}"
fi
NOTARY_ARGS=()
if [[ -n "$NOTARY_PROFILE" ]]; then
    NOTARY_ARGS=(--keychain-profile "$NOTARY_PROFILE")
else
    NOTARY_ARGS=(--key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER")
fi
mkdir -p "$OUTPUT_DIR"
ARCHIVE="$OUTPUT_DIR/VoiceInk.xcarchive"
DERIVED="${VOICEINK_DERIVED_DATA:-$OUTPUT_DIR/dd}"
EXPORT_DIR="$OUTPUT_DIR/export"
rm -rf "$ARCHIVE" "$EXPORT_DIR"

python3 "$SCRIPT_DIR/prepare-local-haas-runtime.py" --sign-identity "$IDENTITY"

echo "Archiving VoiceInk..."
if ! xcodebuild archive \
    -project VoiceInk.xcodeproj \
    -scheme VoiceInk \
    -configuration Release \
    -archivePath "$ARCHIVE" \
    -derivedDataPath "$DERIVED" \
    -xcconfig LocalBuild.xcconfig \
    CODE_SIGN_STYLE=Automatic \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    ARCHS="${VOICEINK_ARCHS:-arm64}" ONLY_ACTIVE_ARCH=NO \
    -allowProvisioningUpdates \
    SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) LOCAL_BUILD' \
    -skipPackagePluginValidation \
    -skipMacroValidation \
    > "$OUTPUT_DIR/archive.log" 2>&1; then
    tail -n 60 "$OUTPUT_DIR/archive.log" >&2
    exit 1
fi

if [[ ! -d "$ARCHIVE" ]]; then
    echo "error: archive failed" >&2
    exit 1
fi

cat > "$OUTPUT_DIR/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>signingCertificate</key>
    <string>Developer ID Application</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
    <key>iCloudContainerEnvironment</key>
    <string>Production</string>
</dict>
</plist>
PLIST

echo "Exporting with Developer ID..."
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$OUTPUT_DIR/ExportOptions.plist" \
    -allowProvisioningUpdates

APP="$EXPORT_DIR/VoiceInk.app"
if [[ ! -d "$APP" ]]; then
    echo "error: exported app not found" >&2
    exit 1
fi
codesign --verify --deep --strict --verbose=2 "$APP"

echo "Preparing dependency notices and corresponding sources..."
python3 "$SCRIPT_DIR/prepare-distribution.py" \
    --source-packages "$DERIVED/SourcePackages/checkouts" \
    --whisper-source "${VOICEINK_WHISPER_SOURCE:-$HOME/VoiceInk-Dependencies/whisper.cpp}" \
    --cache "${VOICEINK_DISTRIBUTION_CACHE:-$OUTPUT_DIR/source-cache}" \
    --output "$OUTPUT_DIR/distribution" --app "$APP"

echo "Packaging DMG..."
DMG=$(VOICEINK_DMG_SIGN_IDENTITY="$IDENTITY" "$SCRIPT_DIR/package-dmg.sh" "$APP" "$OUTPUT_DIR" | tail -n 1)

if [[ "$SKIP_NOTARIZATION" -eq 0 ]]; then
    echo "Submitting for notarization..."
    SUBMIT_OUTPUT=$(xcrun notarytool submit "$DMG" \
        "${NOTARY_ARGS[@]}" 2>&1)
    echo "$SUBMIT_OUTPUT"
    SUBMISSION_ID=$(printf '%s\n' "$SUBMIT_OUTPUT" | awk '/^[[:space:]]*id: /{print $2; exit}')
    if [[ -z "$SUBMISSION_ID" ]]; then
        echo "error: could not read the notarization submission id" >&2
        exit 1
    fi

    # --wait can time out on a slow connection even though Apple keeps processing,
    # so poll the submission instead of failing the whole build.
    while true; do
        INFO=$(xcrun notarytool info "$SUBMISSION_ID" \
            "${NOTARY_ARGS[@]}" 2>&1)
        STATUS=$(printf '%s\n' "$INFO" | awk '/status: /{print $2; exit}')
        echo "notarization status: ${STATUS:-unknown} ($SUBMISSION_ID)"
        case "$STATUS" in
            Accepted) break ;;
            Invalid|Rejected)
                echo "$INFO" >&2
                xcrun notarytool log "$SUBMISSION_ID" \
                    "${NOTARY_ARGS[@]}" >&2 || true
                exit 1
                ;;
        esac
        sleep 20
    done

    xcrun stapler staple "$APP"
    xcrun stapler validate "$APP"
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
    spctl -a -t open --context context:primary-signature -v "$DMG"
fi

# Stapling changes the file, so record the final checksums afterwards.
VERSIONED=$(basename "$DMG")
rm -f "$OUTPUT_DIR/VoiceInk.dmg"
cp "$DMG" "$OUTPUT_DIR/VoiceInk.dmg"
(cd "$OUTPUT_DIR" && shasum -a 256 "$VERSIONED" VoiceInk.dmg > SHA256SUMS)

echo ""
echo "Done: $OUTPUT_DIR/VoiceInk.dmg"
cat "$OUTPUT_DIR/SHA256SUMS"
