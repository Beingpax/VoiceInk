#!/bin/bash

echo "🧹 Cleaning up VoiceInk installations..."

# 1. Remove all VoiceInk apps from Applications
echo "Removing VoiceInk from /Applications..."
rm -rf "/Applications/VoiceInk.app"

# 2. Clean Xcode DerivedData
echo "Cleaning Xcode DerivedData..."
rm -rf ~/Library/Developer/Xcode/DerivedData/VoiceInk-*

# 3. Reset Launch Services database (fixes duplicate app issue)
echo "Resetting Launch Services database..."
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user

# 4. Clear app cache
echo "Clearing app caches..."
rm -rf ~/Library/Caches/com.bharatkumar.VoiceInk
rm -rf ~/Library/Caches/com.prakashjoshipax.VoiceInk

# 5. Clear preferences (optional - uncomment if needed)
# defaults delete com.bharatkumar.VoiceInk
# defaults delete com.prakashjoshipax.VoiceInk

echo "✅ Cleanup complete!"
echo ""
echo "Now rebuild the app with: make build"
