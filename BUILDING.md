# Building VoiceInk

This guide provides detailed instructions for building VoiceInk Community from source. The fork bundles the default Whisper and Parakeet models, so a fresh build is ready to transcribe offline immediately.

## Prerequisites

Before you begin, ensure you have:
- macOS 14.0 or later
- Xcode (latest version recommended)
- Swift (latest version recommended)

## Preload default models (optional but recommended)

Release builds bundle the preferred Whisper binaries. If you are building locally, run:

```bash
./scripts/download-models.sh
```

This script downloads `ggml-base.en.bin` and the quantized large turbo model into `VoiceInk/Resources/Models` so the first launch works offline.

## Building whisper.cpp Framework

VoiceInk relies on [whisper.cpp](https://github.com/ggerganov/whisper.cpp) for on-device transcription. If you have not built the XCFramework yet:

```bash
git clone https://github.com/ggerganov/whisper.cpp.git
cd whisper.cpp
./build-xcframework.sh
```

Drop `build-apple/whisper.xcframework` into the Xcode project (or update the existing reference) before building.

## Building VoiceInk

1. Clone the VoiceInk repository:
```bash
git clone https://github.com/tmm22/VoiceInk.git
cd VoiceInk
```

2. Add the whisper.xcframework to your project:
   - Drag and drop `../whisper.cpp/build-apple/whisper.xcframework` into the project navigator, or
   - Add it manually in the "Frameworks, Libraries, and Embedded Content" section of project settings

3. Build and Run
   - Build the project using Cmd+B or Product > Build
   - Run the project using Cmd+R or Product > Run

## Development Setup

1. **Xcode Configuration**
   - Ensure you have the latest Xcode version
   - Install any required Xcode Command Line Tools

2. **Dependencies**
   - The project uses [whisper.cpp](https://github.com/ggerganov/whisper.cpp) for transcription
   - Ensure the whisper.xcframework is properly linked in your Xcode project
   - Test the whisper.cpp installation independently before proceeding

3. **Building for Development**
   - Use the Debug configuration for development
   - Enable relevant debugging options in Xcode

4. **Testing**
   - Run the test suite before making changes
   - Ensure all tests pass after your modifications

## Troubleshooting

If you encounter any build issues:
1. Clean the build folder (Cmd+Shift+K)
2. Clean the build cache (Cmd+Shift+K twice)
3. Check Xcode and macOS versions
4. Verify all dependencies are properly installed
5. Make sure whisper.xcframework is properly built and linked

For more help, please check the [issues](https://github.com/tmm22/VoiceInk/issues) section or create a new issue. 
