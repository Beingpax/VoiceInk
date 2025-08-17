# Complete Guide to Building VoiceInk from Source

This comprehensive guide will walk you through building VoiceInk from source code and creating a distributable DMG file for installation.

## Your System Status ✅

**Good news!** Your system is already set up correctly:
- **macOS 15.5** ✅ (Requirement: macOS 14.0+)
- **Xcode** ✅ Installed and ready
- **Swift 6.0.3** ✅ Latest version
- **Xcode Command Line Tools** ✅ Available

You don't need to install Swift separately - it comes with Xcode!

## Prerequisites Overview

### What You Need
- **Xcode** (you already have this)
- **Git** (for cloning repositories)
- **Terminal** (for running build commands)
- **About 2-3 GB free disk space** (for whisper.cpp and builds)
- **Time**: Approximately 30-60 minutes for complete build

### What We'll Build
1. **whisper.cpp framework** - The AI transcription engine
2. **VoiceInk app** - The main application
3. **DMG installer** - For easy distribution and installation

## Step 1: Build whisper.cpp Framework

VoiceInk requires the whisper.cpp framework for local AI transcription. This is the most important step.

### 1.1 Create a Working Directory
```bash
# Create a directory for all build files
mkdir ~/VoiceInk-Build
cd ~/VoiceInk-Build
```

### 1.2 Clone and Build whisper.cpp
```bash
# Clone the whisper.cpp repository
git clone https://github.com/ggerganov/whisper.cpp.git
cd whisper.cpp

# Build the XCFramework (this will take 10-20 minutes)
./build-xcframework.sh
```

**What this does:**
- Downloads the whisper.cpp source code
- Compiles it for both Intel and Apple Silicon Macs
- Creates `whisper.xcframework` in `build-apple/` directory

### 1.3 Verify the Build
```bash
# Check if the framework was created successfully
ls -la build-apple/whisper.xcframework
```

You should see a directory structure with the framework files.

## Step 2: Prepare VoiceInk Project

### 2.1 Navigate to VoiceInk Directory
```bash
# Go back to your build directory and navigate to VoiceInk
cd ~/VoiceInk-Build
cd /Users/rohat/dev/github/VoiceInk
```

### 2.2 Add whisper.xcframework to Xcode Project

**Important:** You need to manually add the framework to Xcode:

1. **Open the project in Xcode:**
   ```bash
   open VoiceInk.xcodeproj
   ```

2. **Add the framework:**
   - In Xcode, select the **VoiceInk** project in the navigator (top-level blue icon)
   - Select the **VoiceInk** target under "TARGETS"
   - Go to **"General"** tab
   - Scroll down to **"Frameworks, Libraries, and Embedded Content"**
   - Click the **"+"** button
   - Click **"Add Other..."** → **"Add Files..."**
   - Navigate to: `~/VoiceInk-Build/whisper.cpp/build-apple/whisper.xcframework`
   - Select the framework and click **"Open"**
   - Make sure it's set to **"Embed & Sign"** in the dropdown

## Step 3: Build the VoiceInk App

### 3.1 Build the Project
In Xcode:
1. Select your **target device** (choose "My Mac" from the device dropdown)
2. Press **⌘+B** to build (or go to Product → Build)

**Expected build time:** 2-5 minutes

### 3.2 Test Run (Optional)
Press **⌘+R** to run the app and test it works correctly.

## Step 4: Create Archive for Distribution

### 4.1 Archive the App
1. In Xcode, go to **Product** → **Archive**
2. Wait for the archive process to complete (2-5 minutes)
3. The **Organizer** window will open automatically

### 4.2 Export the App
1. In Organizer, select your archive
2. Click **"Distribute App"**
3. Choose **"Developer ID"** (for distribution outside App Store)
4. Click **"Next"** through the following screens:
   - **"Distribute"** (keep default selections)
   - **"Re-sign"** (keep default selections)
   - **Review** and click **"Export"**
5. Choose a save location (e.g., `~/VoiceInk-Build/Export/`)

This creates a **VoiceInk.app** file that can run on any Mac.

## Step 5: Create DMG Installer

### 5.1 Prepare DMG Contents
```bash
# Create DMG build directory
cd ~/VoiceInk-Build
mkdir DMG-Contents
cd DMG-Contents

# Copy your exported app
cp -R ~/VoiceInk-Build/Export/VoiceInk.app ./

# Create a symlink to Applications folder
ln -s /Applications Applications
```

### 5.2 Create the DMG File
```bash
# Create the DMG installer
hdiutil create -volname "VoiceInk Installer" -srcfolder . -ov -format UDZO ~/VoiceInk-Build/VoiceInk-Installer.dmg
```

### 5.3 Test Your DMG
```bash
# Mount and test the DMG
open ~/VoiceInk-Build/VoiceInk-Installer.dmg
```

## Step 6: Install VoiceInk

### 6.1 Installation Process
1. **Double-click** `VoiceInk-Installer.dmg` to mount it
2. **Drag** `VoiceInk.app` to the `Applications` folder
3. **Eject** the DMG when done
4. **Launch** VoiceInk from Applications folder or Spotlight

### 6.2 First Launch Setup
On first launch, VoiceInk will:
- Request **microphone permissions**
- Request **accessibility permissions** 
- Download additional AI models if needed
- Guide you through onboarding

## Troubleshooting

### Common Issues and Solutions

#### 1. "whisper.xcframework not found"
**Problem:** Build fails because framework isn't properly linked.
**Solution:** 
- Verify `whisper.xcframework` exists in `~/VoiceInk-Build/whisper.cpp/build-apple/`
- Re-add the framework to Xcode project (Step 2.2)
- Clean build folder: Product → Clean Build Folder (⌘+Shift+K)

#### 2. "Build script failed"
**Problem:** whisper.cpp build script fails.
**Solution:**
```bash
# Make sure you have required tools
xcode-select --install

# Try building again
cd ~/VoiceInk-Build/whisper.cpp
make clean
./build-xcframework.sh
```

#### 3. "Code signing failed"
**Problem:** App won't archive due to signing issues.
**Solution:**
- In Xcode, go to Project Settings → Signing & Capabilities
- Change "Team" to your Apple Developer account
- Or choose "Sign to Run Locally" for personal use

### Build Performance Tips

1. **Use SSD storage** for faster builds
2. **Close other apps** during compilation
3. **Use latest Xcode** for best performance
4. **Clean builds** if you encounter strange errors

## File Locations Summary

After completing this guide, you'll have:

```
~/VoiceInk-Build/
├── whisper.cpp/                          # whisper.cpp source
│   └── build-apple/whisper.xcframework   # Built framework
├── Export/VoiceInk.app                   # Exported app bundle
├── DMG-Contents/                         # DMG preparation folder
└── VoiceInk-Installer.dmg               # Final installer
```

## What's Next?

1. **Install and test** VoiceInk from your DMG
2. **Share the DMG** with others who want to use VoiceInk
3. **Contribute** to the project on GitHub
4. **Report issues** if you find any bugs

## Additional Resources

- **VoiceInk GitHub:** https://github.com/Beingpax/VoiceInk
- **whisper.cpp GitHub:** https://github.com/ggerganov/whisper.cpp
- **Apple Developer Documentation:** https://developer.apple.com/documentation/xcode
- **VoiceInk Website:** https://tryvoiceink.com

---

**Congratulations!** You now have a complete, distributable version of VoiceInk that you built yourself from source code. The DMG file works just like commercial software installers - anyone can download it, mount it, and drag the app to their Applications folder.
