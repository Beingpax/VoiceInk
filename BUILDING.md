# Building VoiceInk

This guide provides detailed instructions for building VoiceInk from source.

## Prerequisites

Before you begin, ensure you have:
- macOS 14.4 or later
- Xcode (latest version recommended)
- Swift (latest version recommended)
- Git (for cloning repositories)

## Quick Start with Makefile (Recommended)

The easiest way to build VoiceInk is using the included Makefile, which automates the entire build process including building and linking the whisper framework.

### Simple Build Commands

```bash
# Clone the repository
git clone https://github.com/Beingpax/VoiceInk.git
cd VoiceInk

# Build everything (recommended for first-time setup)
make all

# Or for development (build and run)
make dev
```

### Available Makefile Commands

- `make check` or `make healthcheck` - Verify all required tools are installed
- `make whisper` - Clone and build whisper.cpp XCFramework automatically
- `make setup` - Prepare the whisper framework for linking
- `make build` - Build the VoiceInk Xcode project
- `make local` - Build for local use (no Apple Developer certificate needed)
- `make run` - Launch the built VoiceInk app
- `make dev` - Build and run (ideal for development workflow)
- `make all` - Complete build process (default)
- `make clean` - Remove build artifacts and dependencies
- `make help` - Show all available commands

### How the Makefile Helps

The Makefile automatically:
1. **Manages Dependencies**: Creates a dedicated `~/VoiceInk-Dependencies` directory for all external frameworks
2. **Builds Whisper Framework**: Clones whisper.cpp and builds the XCFramework with the correct configuration
3. **Handles Framework Linking**: Sets up the whisper.xcframework in the proper location for Xcode to find
4. **Verifies Prerequisites**: Checks that git, xcodebuild, and swift are installed before building
5. **Streamlines Development**: Provides convenient shortcuts for common development tasks

This approach ensures consistent builds across different machines and eliminates manual framework setup errors.

---

## Building for Local Use (No Apple Developer Certificate)

If you don't have an Apple Developer certificate, use `make local`:

```bash
git clone https://github.com/Beingpax/VoiceInk.git
cd VoiceInk
make local
open ~/Downloads/VoiceInk.app
```

This builds VoiceInk with ad-hoc signing using a separate build configuration (`LocalBuild.xcconfig`) that requires no Apple Developer account.

### Keeping Accessibility Permission Across Rebuilds

**Symptom:** VoiceInk keeps asking for Accessibility access even though System Settings shows it
already enabled.

**Cause:** macOS records privacy grants (Accessibility, Screen Recording, Microphone) against an
app's *code signature*, not its path. Ad-hoc signing produces a different signature on every build,
so each rebuild looks like a brand-new app and silently loses its permissions. If you also have a
released VoiceInk in `/Applications`, the enabled entry you see in System Settings belongs to *that*
build — the Developer ID signature — which the ad-hoc local build does not match.

**Fix:** create a stable self-signed identity once:

```bash
make local-cert     # or: ./scripts/make-local-signing-cert.sh
```

macOS will prompt for your login password twice (keychain import, then trust setting). After that,
`make local` picks the identity up automatically and the signature stays identical across rebuilds,
so permissions granted once persist.

`make local` re-signs the app with this identity *after* `xcodebuild` finishes, rather than passing
it as a build setting. That is deliberate: the app target defines
`CODE_SIGN_IDENTITY[sdk=macosx*]` at target level, which outranks both the `LocalBuild.xcconfig`
project-level setting and anything passed on the `xcodebuild` command line — Xcode silently signs
ad-hoc instead. Re-signing afterwards is the only reliable override that does not require editing
the shared Xcode project.

You can confirm it worked:

```bash
codesign -dvv ~/Downloads/VoiceInk.app 2>&1 | grep Authority
#   Authority=VoiceInk Local Dev        ← correct
#   (no Authority line, "Signature=adhoc") ← still ad-hoc

codesign -d -r- ~/Downloads/VoiceInk.app
#   designated => identifier "com.prakashjoshipax.VoiceInk" and certificate leaf = H"..."
```

That second command prints the *designated requirement*, which is what macOS matches privacy
grants against. Pinned to `certificate leaf`, it stays the same across rebuilds. Ad-hoc builds
instead print `designated => cdhash H"..."`, which is derived from the binary and therefore changes
every time you build — that is the root cause of the permission prompts.

`VoiceInk.local.entitlements` sets `com.apple.security.cs.disable-library-validation` for the same
reason. A self-signed certificate has no Team ID, and the hardened runtime's library validation
then refuses to load the app's own dylibs and frameworks — the app dies at launch with
`Library not loaded: @rpath/VoiceInk.debug.dylib … different Team IDs`. Ad-hoc builds are exempt
from that check, so it only shows up once you start signing with a real identity. Release builds
use `VoiceInk.entitlements` and keep library validation enabled.

Then grant permission once:

1. Open **System Settings › Privacy & Security › Accessibility**
2. Remove any existing VoiceInk entry (it belongs to a different signature)
3. Run your local build and grant it when asked

To undo: `security delete-certificate -c "VoiceInk Local Dev"`. Without the identity, `make local`
falls back to ad-hoc signing and prints a reminder.

#### If the script fails

Create the certificate through Keychain Access instead — this is Apple's documented path and does
not depend on OpenSSL:

1. Open **Keychain Access**
2. Menu **Keychain Access › Certificate Assistant › Create a Certificate…**
3. Name: `VoiceInk Local Dev`
4. Identity Type: **Self Signed Root**
5. Certificate Type: **Code Signing**
6. Tick **Let me override defaults**, then click Continue through the remaining screens
   (the defaults are fine; give it a long validity such as 3650 days when offered)
7. Verify with `security find-identity -v -p codesigning` — it should list `VoiceInk Local Dev`

`make local` detects it by name, so nothing else needs changing.

### How It Works

The `make local` command uses:
- `LocalBuild.xcconfig` to override signing and entitlements settings
- `VoiceInk.local.entitlements` (stripped-down, no CloudKit/keychain groups)
- `LOCAL_BUILD` Swift compilation flag for conditional code paths
- The `VoiceInk Local Dev` signing identity when present, ad-hoc otherwise

Your normal `make all` / `make build` commands are completely unaffected.

---

## Manual Build Process (Alternative)

If you prefer to build manually or need more control over the build process, follow these steps:

### Building whisper.cpp Framework

1. Clone and build whisper.cpp:
```bash
git clone https://github.com/ggerganov/whisper.cpp.git
cd whisper.cpp
./build-xcframework.sh
```
This will create the XCFramework at `build-apple/whisper.xcframework`.

### Building VoiceInk

1. Clone the VoiceInk repository:
```bash
git clone https://github.com/Beingpax/VoiceInk.git
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

For more help, please check the [issues](https://github.com/Beingpax/VoiceInk/issues) section or create a new issue.
