#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PROJECT_PATH="$REPO_ROOT/VoiceInk.xcodeproj"
SCHEME="VoiceInk"
EXPORT_OPTIONS="$REPO_ROOT/release/ExportOptions.plist"
DMG_ASSET_DIR="$REPO_ROOT/release/dmg"
DMG_LAYOUT="$DMG_ASSET_DIR/layout.conf"
DMG_BACKGROUND="$DMG_ASSET_DIR/background.tiff"
DMG_VOLUME_ICON="$DMG_ASSET_DIR/volume-icon.icns"
WHISPER_FRAMEWORK="${VOICEINK_WHISPER_FRAMEWORK:-$HOME/VoiceInk-Dependencies/whisper.cpp/build-apple/whisper.xcframework}"

DEVELOPER_IDENTITY="${VOICEINK_DEVELOPER_IDENTITY:-Developer ID Application: Prakash Joshi (V6J6A3VWY2)}"
NOTARY_PROFILE="${VOICEINK_NOTARY_PROFILE:-VoiceInk-Notarization}"
SPARKLE_ACCOUNT="${VOICEINK_SPARKLE_ACCOUNT:-VoiceInk}"
RELEASE_BASE_URL="${VOICEINK_RELEASE_BASE_URL:-https://github.com/Beingpax/VoiceInk/releases/download}"
EXPECTED_FEED_URL="https://beingpax.github.io/VoiceInk/appcast.xml"
EXPECTED_BUNDLE_ID="com.prakashjoshipax.VoiceInk"
EXPECTED_MINIMUM_SYSTEM_VERSION="15.0"

XCODE_DEVELOPER_DIR="${VOICEINK_XCODE_DEVELOPER_DIR:-${DEVELOPER_DIR:-}}"
if [[ -z "$XCODE_DEVELOPER_DIR" && -d "/Applications/Xcode.app/Contents/Developer" ]]; then
    XCODE_DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi
if [[ -n "$XCODE_DEVELOPER_DIR" ]]; then
    export DEVELOPER_DIR="$XCODE_DEVELOPER_DIR"
fi

INPUT_APP=""
INPUT_ARCHIVE=""
NOTES_PATH=""
RELEASE_TIMESTAMP="$(date '+%Y-%m-%d_%H-%M-%S')"
RELEASE_OUTPUT_ROOT="${VOICEINK_RELEASE_OUTPUT_ROOT:-$HOME/Downloads/VoiceInk Builds}"
OUTPUT_DIR="$RELEASE_OUTPUT_ROOT/VoiceInk-$RELEASE_TIMESTAMP"
APPCAST_OUTPUT="$REPO_ROOT/appcast.xml"
SKIP_NOTARIZATION=0
ALLOW_DIRTY=0

usage() {
    cat <<'EOF'
Usage:
  scripts/release.sh --notes <release-notes.html> [options]

Builds, signs, notarizes, packages, validates, and creates VoiceInk's Appcast.
The script never commits, pushes, tags, or creates a GitHub release.

Options:
  --app <VoiceInk.app>        Use an existing exported app instead of archiving.
  --archive <file.xcarchive>  Export an existing archive instead of rebuilding.
  --notes <file>              Override release-notes/<app-version>.html.
  --output-dir <directory>    Override the timestamped Downloads directory.
  --appcast-output <file>     Appcast destination (default: ./appcast.xml).
  --notary-profile <name>     notarytool Keychain profile.
  --skip-notarization         Skip Apple submissions; useful for layout testing.
  --allow-dirty               Permit a dirty Git working tree.
  -h, --help                  Show this help.

Examples:
  make release
  make release NOTES=release-notes/2.2.html
  scripts/release.sh --app /path/to/VoiceInk.app \
    --notes /path/to/notes.html --skip-notarization --allow-dirty
EOF
}

log() {
    printf '\n==> %s\n' "$1"
}

fail() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

read_plist_value() {
    plutil -extract "$2" raw "$1"
}

read_image_property() {
    sips -g "$2" "$1" 2>/dev/null | awk -F': ' -v property="$2" \
        '$1 ~ property { print $2; exit }'
}

find_sparkle_tools() {
    if [[ -n "${SPARKLE_BIN_DIR:-}" ]]; then
        [[ -x "$SPARKLE_BIN_DIR/generate_appcast" ]] || fail "generate_appcast not found in SPARKLE_BIN_DIR"
        return
    fi

    local candidate
    candidate="$(find "$HOME/Library/Developer/Xcode/DerivedData" \
        -path '*/VoiceInk-*/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast' \
        -type f -perm -111 -print -quit 2>/dev/null || true)"
    if [[ -z "$candidate" ]]; then
        candidate="$(find "$HOME/Library/Developer/Xcode/DerivedData" \
            -path '*/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast' \
            -type f -perm -111 -print -quit 2>/dev/null || true)"
    fi
    [[ -n "$candidate" ]] || fail "Sparkle tools not found. Resolve VoiceInk's Swift packages first."
    SPARKLE_BIN_DIR="$(dirname "$candidate")"
}

cleanup_mount() {
    if [[ "${DMG_MOUNTED:-0}" == "1" && -n "${DMG_MOUNT_DIR:-}" ]]; then
        hdiutil detach "$DMG_MOUNT_DIR" >/dev/null 2>&1 || true
    fi
}

trap cleanup_mount EXIT

while [[ $# -gt 0 ]]; do
    case "$1" in
        --app)
            [[ $# -ge 2 ]] || fail "--app requires a path"
            INPUT_APP="$2"
            shift 2
            ;;
        --archive)
            [[ $# -ge 2 ]] || fail "--archive requires a path"
            INPUT_ARCHIVE="$2"
            shift 2
            ;;
        --notes)
            [[ $# -ge 2 ]] || fail "--notes requires a path"
            NOTES_PATH="$2"
            shift 2
            ;;
        --output-dir)
            [[ $# -ge 2 ]] || fail "--output-dir requires a path"
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --appcast-output)
            [[ $# -ge 2 ]] || fail "--appcast-output requires a path"
            APPCAST_OUTPUT="$2"
            shift 2
            ;;
        --notary-profile)
            [[ $# -ge 2 ]] || fail "--notary-profile requires a name"
            NOTARY_PROFILE="$2"
            shift 2
            ;;
        --skip-notarization)
            SKIP_NOTARIZATION=1
            shift
            ;;
        --allow-dirty)
            ALLOW_DIRTY=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            fail "Unknown argument: $1"
            ;;
    esac
done

if [[ -n "$INPUT_APP" && -n "$INPUT_ARCHIVE" ]]; then
    fail "--app and --archive cannot be used together"
fi
if [[ -z "$INPUT_APP" && -z "$INPUT_ARCHIVE" && ! -d "$WHISPER_FRAMEWORK" ]]; then
    fail "Whisper framework not found: $WHISPER_FRAMEWORK. Run: make whisper"
fi
[[ -f "$EXPORT_OPTIONS" ]] || fail "Export options not found: $EXPORT_OPTIONS"
[[ -f "$DMG_LAYOUT" ]] || fail "DMG layout not found: $DMG_LAYOUT"
[[ -f "$DMG_BACKGROUND" ]] || fail "DMG background not found: $DMG_BACKGROUND"
[[ -f "$DMG_VOLUME_ICON" ]] || fail "DMG volume icon not found: $DMG_VOLUME_ICON"

# shellcheck source=../release/dmg/layout.conf
source "$DMG_LAYOUT"

require_command codesign
require_command create-dmg
require_command ditto
require_command git
require_command hdiutil
require_command plutil
require_command security
require_command shasum
require_command sips
require_command spctl
require_command stat
require_command xcrun
require_command xmllint

BACKGROUND_PIXEL_WIDTH="$(read_image_property "$DMG_BACKGROUND" pixelWidth)"
BACKGROUND_PIXEL_HEIGHT="$(read_image_property "$DMG_BACKGROUND" pixelHeight)"
BACKGROUND_DPI_WIDTH="$(read_image_property "$DMG_BACKGROUND" dpiWidth)"
BACKGROUND_DPI_HEIGHT="$(read_image_property "$DMG_BACKGROUND" dpiHeight)"

[[ "$BACKGROUND_PIXEL_WIDTH" == "$DMG_BACKGROUND_PIXEL_WIDTH" ]] \
    || fail "DMG background width must be $DMG_BACKGROUND_PIXEL_WIDTH pixels"
[[ "$BACKGROUND_PIXEL_HEIGHT" == "$DMG_BACKGROUND_PIXEL_HEIGHT" ]] \
    || fail "DMG background height must be $DMG_BACKGROUND_PIXEL_HEIGHT pixels"
[[ "${BACKGROUND_DPI_WIDTH%%.*}" == "$DMG_BACKGROUND_DPI" ]] \
    || fail "DMG background horizontal DPI must be $DMG_BACKGROUND_DPI"
[[ "${BACKGROUND_DPI_HEIGHT%%.*}" == "$DMG_BACKGROUND_DPI" ]] \
    || fail "DMG background vertical DPI must be $DMG_BACKGROUND_DPI"

find_sparkle_tools
GENERATE_APPCAST="$SPARKLE_BIN_DIR/generate_appcast"
GENERATE_KEYS="$SPARKLE_BIN_DIR/generate_keys"
SIGN_UPDATE="$SPARKLE_BIN_DIR/sign_update"

[[ -x "$GENERATE_KEYS" ]] || fail "Sparkle generate_keys tool not found"
[[ -x "$SIGN_UPDATE" ]] || fail "Sparkle sign_update tool not found"

security find-identity -v -p codesigning | grep -F "$DEVELOPER_IDENTITY" >/dev/null \
    || fail "Developer ID signing identity is unavailable: $DEVELOPER_IDENTITY"

if [[ "$SKIP_NOTARIZATION" == "0" ]]; then
    log "Checking notarization credentials"
    xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" --output-format json >/dev/null \
        || fail "Notarization profile '$NOTARY_PROFILE' is unavailable. Run: make release-setup"
fi

if [[ "$ALLOW_DIRTY" == "0" && -n "$(git -C "$REPO_ROOT" status --porcelain)" ]]; then
    fail "Git working tree is not clean. Commit/stash changes or pass --allow-dirty."
fi

if [[ -e "$OUTPUT_DIR" && -n "$(find "$OUTPUT_DIR" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
    fail "Output directory is not empty: $OUTPUT_DIR"
fi

mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"
EXPORT_DIR="$OUTPUT_DIR/export"
WORK_DIR="$OUTPUT_DIR/work"
ARCHIVE_PATH="$OUTPUT_DIR/VoiceInk.xcarchive"
DMG_PATH="$OUTPUT_DIR/VoiceInk.dmg"
mkdir -p "$EXPORT_DIR" "$WORK_DIR"

if [[ -n "$INPUT_APP" ]]; then
    [[ -d "$INPUT_APP" ]] || fail "Input app not found: $INPUT_APP"
    log "Copying existing application"
    ditto "$INPUT_APP" "$EXPORT_DIR/VoiceInk.app"
else
    require_command xcodebuild
    if [[ -n "$INPUT_ARCHIVE" ]]; then
        [[ -d "$INPUT_ARCHIVE" ]] || fail "Input archive not found: $INPUT_ARCHIVE"
        ARCHIVE_PATH="$INPUT_ARCHIVE"
    else
        log "Archiving VoiceInk"
        xcodebuild archive \
            -project "$PROJECT_PATH" \
            -scheme "$SCHEME" \
            -configuration Release \
            -archivePath "$ARCHIVE_PATH"
    fi

    log "Exporting Developer ID application"
    xcodebuild -exportArchive \
        -archivePath "$ARCHIVE_PATH" \
        -exportPath "$EXPORT_DIR" \
        -exportOptionsPlist "$EXPORT_OPTIONS"
fi

APP_PATH="$EXPORT_DIR/VoiceInk.app"
INFO_PLIST="$APP_PATH/Contents/Info.plist"
[[ -d "$APP_PATH" ]] || fail "Exported VoiceInk.app not found"
[[ -f "$INFO_PLIST" ]] || fail "Exported app Info.plist not found"

SHORT_VERSION="$(read_plist_value "$INFO_PLIST" CFBundleShortVersionString)"
BUILD_VERSION="$(read_plist_value "$INFO_PLIST" CFBundleVersion)"
MINIMUM_SYSTEM_VERSION="$(read_plist_value "$INFO_PLIST" LSMinimumSystemVersion)"
BUNDLE_ID="$(read_plist_value "$INFO_PLIST" CFBundleIdentifier)"
FEED_URL="$(read_plist_value "$INFO_PLIST" SUFeedURL)"
APP_PUBLIC_KEY="$(read_plist_value "$INFO_PLIST" SUPublicEDKey)"
RELEASE_TAG="v$SHORT_VERSION"
DOWNLOAD_URL="$RELEASE_BASE_URL/$RELEASE_TAG/VoiceInk.dmg"

if [[ -z "$NOTES_PATH" ]]; then
    NOTES_PATH="$REPO_ROOT/release-notes/$SHORT_VERSION.html"
elif [[ "$NOTES_PATH" != /* ]]; then
    NOTES_PATH="$REPO_ROOT/$NOTES_PATH"
fi
[[ -f "$NOTES_PATH" ]] || fail "Release notes not found: $NOTES_PATH"

NOTES_EXTENSION="${NOTES_PATH##*.}"
NOTES_EXTENSION="$(printf '%s' "$NOTES_EXTENSION" | tr '[:upper:]' '[:lower:]')"
case "$NOTES_EXTENSION" in
    html|md|txt) ;;
    *) fail "Release notes must use .html, .md, or .txt" ;;
esac

[[ "$BUNDLE_ID" == "$EXPECTED_BUNDLE_ID" ]] || fail "Unexpected bundle identifier: $BUNDLE_ID"
[[ "$FEED_URL" == "$EXPECTED_FEED_URL" ]] || fail "Unexpected Sparkle feed URL: $FEED_URL"
[[ "$MINIMUM_SYSTEM_VERSION" == "$EXPECTED_MINIMUM_SYSTEM_VERSION" ]] \
    || fail "Unexpected minimum system version: $MINIMUM_SYSTEM_VERSION (expected $EXPECTED_MINIMUM_SYSTEM_VERSION)"
[[ "$BUILD_VERSION" =~ ^[0-9]+$ ]] || fail "CFBundleVersion must be numeric: $BUILD_VERSION"

log "Verifying application signature and Sparkle key"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
KEYCHAIN_PUBLIC_KEY="$("$GENERATE_KEYS" --account "$SPARKLE_ACCOUNT" -p)"
[[ "$KEYCHAIN_PUBLIC_KEY" == "$APP_PUBLIC_KEY" ]] || fail "Sparkle Keychain public key does not match the app"

if [[ "$SKIP_NOTARIZATION" == "0" ]]; then
    APP_ZIP="$WORK_DIR/VoiceInk.zip"
    log "Submitting application for notarization"
    ditto -c -k --keepParent "$APP_PATH" "$APP_ZIP"
    xcrun notarytool submit "$APP_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP_PATH"
    xcrun stapler validate "$APP_PATH"
    spctl -a -t exec -vv "$APP_PATH"
else
    log "Skipping application notarization"
fi

DMG_SOURCE_DIR="$WORK_DIR/dmg-source"
mkdir -p "$DMG_SOURCE_DIR"
ditto "$APP_PATH" "$DMG_SOURCE_DIR/VoiceInk.app"

log "Building DMG with extracted DMG Canvas layout"
create-dmg \
    --volname "$DMG_VOLUME_NAME" \
    --volicon "$DMG_VOLUME_ICON" \
    --background "$DMG_BACKGROUND" \
    --window-pos "$DMG_WINDOW_X" "$DMG_WINDOW_Y" \
    --window-size "$DMG_WINDOW_WIDTH" "$DMG_WINDOW_HEIGHT" \
    --text-size "$DMG_TEXT_SIZE" \
    --icon-size "$DMG_ICON_SIZE" \
    --icon "VoiceInk.app" "$DMG_APP_X" "$DMG_APP_Y" \
    --hide-extension "VoiceInk.app" \
    --app-drop-link "$DMG_APPLICATIONS_X" "$DMG_APPLICATIONS_Y" \
    --filesystem APFS \
    --format ULFO \
    --no-internet-enable \
    "$DMG_PATH" \
    "$DMG_SOURCE_DIR"

log "Code signing DMG"
codesign --force --timestamp --sign "$DEVELOPER_IDENTITY" "$DMG_PATH"
codesign --verify --deep --strict --verbose=2 "$DMG_PATH"

if [[ "$SKIP_NOTARIZATION" == "0" ]]; then
    log "Submitting DMG for notarization"
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"
    spctl -a -t open --context context:primary-signature -vv "$DMG_PATH"
else
    log "Skipping DMG notarization"
fi

log "Validating DMG contents"
hdiutil verify "$DMG_PATH"
DMG_MOUNT_DIR="$(mktemp -d /tmp/voiceink-release-mount.XXXXXX)"
hdiutil attach -readonly -nobrowse -mountpoint "$DMG_MOUNT_DIR" "$DMG_PATH"
DMG_MOUNTED=1

MOUNTED_APP="$DMG_MOUNT_DIR/VoiceInk.app"
[[ -d "$MOUNTED_APP" ]] || fail "VoiceInk.app is missing from the DMG"
[[ -L "$DMG_MOUNT_DIR/Applications" ]] || fail "Applications shortcut is missing from the DMG"
[[ "$(read_plist_value "$MOUNTED_APP/Contents/Info.plist" CFBundleShortVersionString)" == "$SHORT_VERSION" ]] \
    || fail "DMG app short version does not match"
[[ "$(read_plist_value "$MOUNTED_APP/Contents/Info.plist" CFBundleVersion)" == "$BUILD_VERSION" ]] \
    || fail "DMG app build version does not match"
[[ "$(read_plist_value "$MOUNTED_APP/Contents/Info.plist" SUPublicEDKey)" == "$APP_PUBLIC_KEY" ]] \
    || fail "DMG app Sparkle public key does not match"
codesign --verify --deep --strict --verbose=2 "$MOUNTED_APP"

hdiutil detach "$DMG_MOUNT_DIR"
DMG_MOUNTED=0

APPCAST_WORK_DIR="$WORK_DIR/appcast"
mkdir -p "$APPCAST_WORK_DIR"
ditto "$DMG_PATH" "$APPCAST_WORK_DIR/VoiceInk.dmg"
cp "$NOTES_PATH" "$APPCAST_WORK_DIR/VoiceInk.$NOTES_EXTENSION"

log "Generating Sparkle Appcast"
"$GENERATE_APPCAST" \
    --account "$SPARKLE_ACCOUNT" \
    --download-url-prefix "$RELEASE_BASE_URL/$RELEASE_TAG/" \
    --embed-release-notes \
    --versions "$BUILD_VERSION" \
    "$APPCAST_WORK_DIR"

GENERATED_APPCAST="$APPCAST_WORK_DIR/appcast.xml"
[[ -f "$GENERATED_APPCAST" ]] || fail "Sparkle did not generate appcast.xml"
xmllint --noout "$GENERATED_APPCAST"

APPCAST_VERSION="$(xmllint --xpath "string(//*[local-name()='item']/*[local-name()='version'])" "$GENERATED_APPCAST")"
APPCAST_SHORT_VERSION="$(xmllint --xpath "string(//*[local-name()='item']/*[local-name()='shortVersionString'])" "$GENERATED_APPCAST")"
APPCAST_MINIMUM_SYSTEM="$(xmllint --xpath "string(//*[local-name()='item']/*[local-name()='minimumSystemVersion'])" "$GENERATED_APPCAST")"
APPCAST_URL="$(xmllint --xpath "string(//*[local-name()='item']/*[local-name()='enclosure']/@url)" "$GENERATED_APPCAST")"
APPCAST_LENGTH="$(xmllint --xpath "string(//*[local-name()='item']/*[local-name()='enclosure']/@length)" "$GENERATED_APPCAST")"
APPCAST_SIGNATURE="$(xmllint --xpath "string(//*[local-name()='item']/*[local-name()='enclosure']/@*[local-name()='edSignature'])" "$GENERATED_APPCAST")"
DMG_LENGTH="$(stat -f '%z' "$DMG_PATH")"

[[ "$APPCAST_VERSION" == "$BUILD_VERSION" ]] || fail "Appcast build version does not match"
[[ "$APPCAST_SHORT_VERSION" == "$SHORT_VERSION" ]] || fail "Appcast short version does not match"
[[ "$APPCAST_MINIMUM_SYSTEM" == "$MINIMUM_SYSTEM_VERSION" ]] || fail "Appcast minimum system version does not match"
[[ "$APPCAST_URL" == "$DOWNLOAD_URL" ]] || fail "Unexpected Appcast download URL: $APPCAST_URL"
[[ "$APPCAST_LENGTH" == "$DMG_LENGTH" ]] || fail "Appcast DMG length does not match"
[[ -n "$APPCAST_SIGNATURE" ]] || fail "Appcast is missing the Sparkle EdDSA signature"
"$SIGN_UPDATE" --account "$SPARKLE_ACCOUNT" --verify "$DMG_PATH" "$APPCAST_SIGNATURE"

RELEASE_APPCAST="$OUTPUT_DIR/appcast.xml"
cp "$GENERATED_APPCAST" "$RELEASE_APPCAST"
xmllint --noout "$RELEASE_APPCAST"

mkdir -p "$(dirname "$APPCAST_OUTPUT")"
if [[ "$APPCAST_OUTPUT" != "$RELEASE_APPCAST" ]]; then
    cp "$GENERATED_APPCAST" "$APPCAST_OUTPUT"
fi
xmllint --noout "$APPCAST_OUTPUT"

DMG_SHA256="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"

printf '\nRelease prepared successfully.\n'
printf 'Version:       %s\n' "$SHORT_VERSION"
printf 'Build:         %s\n' "$BUILD_VERSION"
printf 'DMG:           %s\n' "$DMG_PATH"
printf 'DMG bytes:     %s\n' "$DMG_LENGTH"
printf 'DMG SHA-256:   %s\n' "$DMG_SHA256"
printf 'Artifacts:     %s\n' "$OUTPUT_DIR"
printf 'Appcast:       %s\n' "$RELEASE_APPCAST"
printf 'Repository:    %s\n' "$APPCAST_OUTPUT"
printf 'Download URL:  %s\n' "$DOWNLOAD_URL"
if [[ "$SKIP_NOTARIZATION" == "1" ]]; then
    printf 'Notarization:  skipped (test artifact only)\n'
else
    printf 'Notarization:  app and DMG accepted and stapled\n'
fi
