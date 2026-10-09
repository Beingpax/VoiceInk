#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
atomics_path="$repo_root/.local-build/SourcePackages/checkouts/swift-atomics"
if [[ ! -d "$atomics_path" ]]; then
  echo 'Resolve the Xcode packages into .local-build first.' >&2
  exit 1
fi
probe_dir="$(mktemp -d "${TMPDIR:-/tmp}/voiceink-capture-test.XXXXXX")"
trap 'rm -rf "$probe_dir"' EXIT
mkdir -p "$probe_dir/Sources/Probe"
cp "$repo_root/VoiceInk/Infrastructure/Audio/CoreAudioRecorder.swift" "$probe_dir/Sources/Probe/"
cp "$repo_root/Tests/AudioCaptureRegression/main.swift" "$probe_dir/Sources/Probe/"
# Keep dependency discovery independent of spaces in the checkout path.
ln -s "$atomics_path" "$probe_dir/swift-atomics"
cat > "$probe_dir/Package.swift" <<'PACKAGE'
// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "Probe", platforms: [.macOS(.v14)], dependencies: [.package(path: "swift-atomics")], targets: [.executableTarget(name: "Probe", dependencies: [.product(name: "Atomics", package: "swift-atomics")])], swiftLanguageModes: [.v5])
PACKAGE
swift run --package-path "$probe_dir" Probe "$@"
