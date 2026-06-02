#!/bin/bash
# Deploy VoiceInk without breaking Input Monitoring
# Uses stable Developer identity so macOS never revokes permissions
set -e
SRC=".local-build/Build/Products/Debug/VoiceInk.app"
DST="/Applications/VoiceInk.app"
IDENTITY="Apple Development: abel.wang@thrivent.com (ADU92LKRFT)"

killall VoiceInk 2>/dev/null || true
sleep 0.5

rsync -a --delete "$SRC/" "$DST/"
codesign --force --deep --sign "$IDENTITY" "$DST"

echo "✓ Deployed + signed with stable identity. Launching..."
open "$DST"
