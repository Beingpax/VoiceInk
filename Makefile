# Define a directory for dependencies in the user's home folder
DEPS_DIR := $(HOME)/VoiceInk-Dependencies
WHISPER_CPP_DIR := $(DEPS_DIR)/whisper.cpp
FRAMEWORK_PATH := $(WHISPER_CPP_DIR)/build-apple/whisper.xcframework

.PHONY: all clean whisper setup build build-release check healthcheck help dev run dmg

# Default target
all: check build

# Development workflow
dev: build run

# Prerequisites
check:
	@echo "Checking prerequisites..."
	@command -v git >/dev/null 2>&1 || { echo "git is not installed"; exit 1; }
	@command -v xcodebuild >/dev/null 2>&1 || { echo "xcodebuild is not installed (need Xcode)"; exit 1; }
	@command -v swift >/dev/null 2>&1 || { echo "swift is not installed"; exit 1; }
	@echo "Prerequisites OK"

healthcheck: check

# Build process
whisper:
	@mkdir -p $(DEPS_DIR)
	@if [ ! -d "$(FRAMEWORK_PATH)" ]; then \
		echo "Building whisper.xcframework in $(DEPS_DIR)..."; \
		if [ ! -d "$(WHISPER_CPP_DIR)" ]; then \
			git clone https://github.com/ggerganov/whisper.cpp.git $(WHISPER_CPP_DIR); \
		else \
			(cd $(WHISPER_CPP_DIR) && git pull); \
		fi; \
		cd $(WHISPER_CPP_DIR) && ./build-xcframework.sh; \
	else \
		echo "whisper.xcframework already built in $(DEPS_DIR), skipping build"; \
	fi

setup: whisper
	@echo "Whisper framework is ready at $(FRAMEWORK_PATH)"
	@echo "Please ensure your Xcode project references the framework from this new location."

build: setup
	xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGN_ENTITLEMENTS="" DEVELOPMENT_TEAM="" ENABLE_HARDENED_RUNTIME=NO SWIFT_VERSION=5.0 build

# Build Release version (for distribution)
build-release: setup
	@echo "Building Release version..."
	xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Release CODE_SIGN_STYLE=Automatic SWIFT_VERSION=5.0 build
	@echo "Release build complete. App location:"
	@find "$$HOME/Library/Developer/Xcode/DerivedData" -name "VoiceInk.app" -path "*/Release/*" -type d | head -1

# Create DMG installer
dmg: build-release
	@echo "Creating DMG installer..."
	@APP_PATH=$$(find "$$HOME/Library/Developer/Xcode/DerivedData" -name "VoiceInk.app" -path "*/Release/*" -type d | head -1) && \
	if [ -n "$$APP_PATH" ]; then \
		rm -f VoiceInk.dmg; \
		hdiutil create -volname "VoiceInk" -srcfolder "$$APP_PATH" -ov -format UDZO VoiceInk.dmg; \
		echo "DMG created: $$(pwd)/VoiceInk.dmg"; \
	else \
		echo "Release build not found. Run 'make build-release' first."; \
		exit 1; \
	fi

# Run application
run:
	@echo "Looking for VoiceInk.app..."
	@APP_PATH=$$(find "$$HOME/Library/Developer/Xcode/DerivedData" -name "VoiceInk.app" -type d | head -1) && \
	if [ -n "$$APP_PATH" ]; then \
		echo "Found app at: $$APP_PATH"; \
		open "$$APP_PATH"; \
	else \
		echo "VoiceInk.app not found. Please run 'make build' first."; \
		exit 1; \
	fi

# Cleanup
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(DEPS_DIR)
	@echo "Clean complete"

# Help
help:
	@echo "Available targets:"
	@echo "  check/healthcheck  Check if required CLI tools are installed"
	@echo "  whisper            Clone and build whisper.cpp XCFramework"
	@echo "  setup              Copy whisper XCFramework to VoiceInk project"
	@echo "  build              Build the VoiceInk Xcode project (Debug)"
	@echo "  build-release      Build Release version for distribution"
	@echo "  dmg                Create DMG installer (builds Release first)"
	@echo "  run                Launch the built VoiceInk app"
	@echo "  dev                Build and run the app (for development)"
	@echo "  all                Run full build process (default)"
	@echo "  clean              Remove build artifacts"
	@echo "  help               Show this help message"