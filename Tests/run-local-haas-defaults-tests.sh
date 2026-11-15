#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP="$(mktemp -d /tmp/voiceink-haas-defaults.XXXXXX)"
trap 'rm -rf "$TEMP"' EXIT
swiftc -module-cache-path "$TEMP/module-cache" -parse-as-library \
    "$ROOT/VoiceInk/Features/ModelLibrary/Models/TranscriptionModel.swift" \
    "$ROOT/VoiceInk/App/Configuration/LocalHaasSettings.swift" \
    "$ROOT/VoiceInk/Infrastructure/Providers/Transcription/Cloud/OpenAICompatibleTranscriptionService.swift" \
    "$ROOT/VoiceInk/App/Configuration/LocalHaasModelStore.swift" \
    "$ROOT/VoiceInk/App/Configuration/LocalHaasProcess.swift" \
    "$ROOT/VoiceInk/App/Configuration/LocalHaasRuntime.swift" \
    "$ROOT/Tests/LocalHaasTestSupport.swift" \
    "$ROOT/Tests/LocalHaasDefaultsTests.swift" -o "$TEMP/tests"
"$TEMP/tests"
