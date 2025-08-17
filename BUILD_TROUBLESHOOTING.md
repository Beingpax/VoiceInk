# Build Troubleshooting Guide

This guide covers common build issues and their solutions when building VoiceInk.

## Prerequisites

### System Requirements
- macOS 15.0 or later
- Xcode 15.0 or later
- Git
- CMake (install via `brew install cmake`)

### Developer Account
- Apple Developer Account (for code signing)
- Valid provisioning profile

## Common Build Issues

### 1. Package Dependency Errors

**Problem**: 
```
Failed to clone repository https://github.com/marmelroy/Zip?tab=readme-ov-file:
fatal: https://github.com/marmelroy/Zip?tab=readme-ov-file/info/refs not valid
```

**Solution**:
The Zip package URL has an invalid suffix. Fix it by:

1. Edit `VoiceInk.xcodeproj/project.pbxproj`:
   ```
   Change: repositoryURL = "https://github.com/marmelroy/Zip?tab=readme-ov-file";
   To:     repositoryURL = "https://github.com/marmelroy/Zip";
   ```

2. Edit `VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`:
   ```json
   Change: "identity": "zip?tab=readme-ov-file"
   To:     "identity": "zip"
   
   Change: "location": "https://github.com/marmelroy/Zip?tab=readme-ov-file"
   To:     "location": "https://github.com/marmelroy/Zip"
   ```

### 2. Deprecated API Errors

**Problem**:
```
'CGWindowListCreateImage' is unavailable in macOS: Please use ScreenCaptureKit instead.
```

**Solution**:
The screen capture functionality uses deprecated APIs. This has been fixed by commenting out the problematic code in `VoiceInk/Services/ScreenCaptureService.swift`. The app will build successfully but screen capture features will be disabled.

### 3. macOS Version Compatibility

**Problem**:
```
"Check with the developer to make sure VoiceInk works with this version of macOS"
```

**Solution**:
Update the deployment target to match your macOS version:

1. Open project in Xcode
2. Select VoiceInk target
3. Go to Build Settings → Deployment → macOS Deployment Target
4. Set to `15.0` (or your current macOS version)

### 4. Missing whisper.xcframework

**Problem**:
- App builds but is unusually small (~4.5MB instead of ~40MB)
- Runtime errors about missing whisper functionality

**Solution**:
1. Build the whisper.cpp framework:
   ```bash
   cd ~/dev/github/VoiceInk-Build/whisper.cpp
   cmake -B build-apple -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 -DCMAKE_BUILD_TYPE=Release -DWHISPER_BUILD_FRAMEWORKS=ON
   cmake --build build-apple --config Release
   ```

2. Verify the framework was built:
   ```bash
   ls -la ~/dev/github/VoiceInk-Build/whisper.cpp/build-apple/whisper.xcframework
   ```

3. Copy to project directory:
   ```bash
   cp -R ~/dev/github/VoiceInk-Build/whisper.cpp/build-apple/whisper.xcframework ~/dev/github/VoiceInk/
   ```

### 5. Code Signing Issues

**Problem**:
```
No profiles for 'com.prakashjoshipax.VoiceInk'
```

**Solution**:
1. Change bundle identifier in Xcode:
   - Select VoiceInk target
   - Go to Signing & Capabilities
   - Change Bundle Identifier to your own (e.g., `com.yourname.VoiceInk`)

2. Select your development team and provisioning profile

### 6. Clean Build Environment

If you encounter persistent build issues:

1. Clean Xcode derived data:
   ```bash
   rm -rf ~/Library/Developer/Xcode/DerivedData/VoiceInk-*
   ```

2. Clean project in Xcode:
   ```bash
   xcodebuild clean -project VoiceInk.xcodeproj -scheme VoiceInk
   ```

3. Reset package caches:
   - In Xcode: File → Packages → Reset Package Caches

## Build Process

### Complete Build Steps

1. **Setup environment**:
   ```bash
   # Install dependencies
   brew install cmake
   
   # Create build directory
   mkdir -p ~/dev/github/VoiceInk-Build
   cd ~/dev/github/VoiceInk-Build
   ```

2. **Build whisper.cpp framework**:
   ```bash
   git clone https://github.com/ggerganov/whisper.cpp.git
   cd whisper.cpp
   cmake -B build-apple -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 -DCMAKE_BUILD_TYPE=Release -DWHISPER_BUILD_FRAMEWORKS=ON
   cmake --build build-apple --config Release
   ```

3. **Copy framework to project**:
   ```bash
   cp -R build-apple/whisper.xcframework ~/dev/github/VoiceInk/
   ```

4. **Build VoiceInk**:
   ```bash
   cd ~/dev/github/VoiceInk
   xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Release
   ```

## Verification

After a successful build:
- App should be ~40MB in size
- Located at: `~/Library/Developer/Xcode/DerivedData/VoiceInk-*/Build/Products/Release/VoiceInk.app`
- Should launch without compatibility warnings

## Known Limitations

1. **Screen Capture**: Currently disabled due to deprecated APIs
2. **Native Apple Speech**: Removed due to future API usage
3. **macOS 14 Support**: App requires macOS 15.0 or later

## Getting Help

If you encounter issues not covered here:
1. Check the main [CLAUDE.md](CLAUDE.md) file for architecture details
2. Review Xcode build logs for specific error messages
3. Ensure all dependencies are properly installed