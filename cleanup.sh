#!/bin/bash

echo "🧹 Cleaning up VoiceInk caches and build artifacts..."

# 1. Remove all VoiceInk apps from Applications
echo "1. Removing VoiceInk from /Applications..."
rm -rf "/Applications/VoiceInk.app"

# 2. Clean Xcode DerivedData
echo "2. Cleaning Xcode DerivedData..."
rm -rf ~/Library/Developer/Xcode/DerivedData/VoiceInk-*

# 3. Clear app caches
echo "3. Clearing app caches..."
rm -rf ~/Library/Caches/com.bharatkumar.VoiceInk
rm -rf ~/Library/Caches/com.prakashjoshipax.VoiceInk

# 4. Clear app preferences
echo "4. Clearing app preferences..."
defaults delete com.bharatkumar.VoiceInk 2>/dev/null || true
defaults delete com.prakashjoshipax.VoiceInk 2>/dev/null || true

# 5. Clear application support
echo "5. Clearing Application Support..."
rm -rf ~/Library/Application\ Support/VoiceInk
rm -rf ~/Library/Application\ Support/com.bharatkumar.VoiceInk
rm -rf ~/Library/Application\ Support/com.prakashjoshipax.VoiceInk

# 6. Clear saved application state
echo "6. Clearing saved application state..."
rm -rf ~/Library/Saved\ Application\ State/com.bharatkumar.VoiceInk.savedState
rm -rf ~/Library/Saved\ Application\ State/com.prakashjoshipax.VoiceInk.savedState

# 7. Clear logs
echo "7. Clearing logs..."
rm -rf ~/Library/Logs/VoiceInk

# 8. Reset Launch Services database
echo "8. Resetting Launch Services database..."
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user

# 9. Clean local build artifacts
echo "9. Cleaning local build artifacts..."
rm -f VoiceInk.dmg
rm -rf build/

echo ""
echo "✅ Cleanup complete!"
echo ""
echo "Next steps:"
echo "  1. Run: make build"
echo "  2. Or run: make dmg (to create installer)"
