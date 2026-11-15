# Define a directory for dependencies in the user's home folder
DEPS_DIR := $(HOME)/VoiceInk-Dependencies
WHISPER_CPP_DIR := $(DEPS_DIR)/whisper.cpp
FRAMEWORK_PATH := $(WHISPER_CPP_DIR)/build-apple/whisper.xcframework
LOCAL_DERIVED_DATA := $(CURDIR)/.local-build
LOCAL_CODESIGN_IDENTITY ?= Apple Development
APP_OUTPUT_DIR ?= $(HOME)/Downloads
RUN_APP_NAME ?= VoiceInk

.PHONY: all clean whisper setup build local check healthcheck help dev run release release-setup personal-dmg package-dmg

# Default target
all: check build

# Development workflow
dev: RUN_APP_NAME = VoiceInk Dev
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
.PHONY: local-haas-runtime
local-haas-runtime:
	python3 scripts/prepare-local-haas-runtime.py

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

setup: whisper local-haas-runtime
	@echo "Whisper framework is ready at $(FRAMEWORK_PATH)"
	@echo "Please ensure your Xcode project references the framework from this new location."

build: setup
	xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Debug CODE_SIGN_IDENTITY="" \
		-skipPackagePluginValidation \
		-skipMacroValidation \
		build

# Build locally with automatic Apple Development signing and the configured iCloud container.
local: check setup
	@echo "Building VoiceInk for local use with automatic Apple Development signing..."
	@rm -rf "$(LOCAL_DERIVED_DATA)"
	@SIGNING_IDENTITY="$(LOCAL_CODESIGN_IDENTITY)"; \
	if [ -z "$$SIGNING_IDENTITY" ]; then SIGNING_IDENTITY="Apple Development"; fi; \
	xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Release \
		-derivedDataPath "$(LOCAL_DERIVED_DATA)" \
		-xcconfig LocalBuild.xcconfig \
		CODE_SIGN_IDENTITY="$$SIGNING_IDENTITY" \
		CODE_SIGNING_REQUIRED=YES \
		CODE_SIGNING_ALLOWED=YES \
		-allowProvisioningUpdates \
		SWIFT_ACTIVE_COMPILATION_CONDITIONS='$$(inherited) LOCAL_BUILD' \
		-skipPackagePluginValidation \
		-skipMacroValidation \
		build
	@APP_PATH="$(LOCAL_DERIVED_DATA)/Build/Products/Release/VoiceInk.app" && \
	if [ -d "$$APP_PATH" ]; then \
		DESTINATION="$(APP_OUTPUT_DIR)/VoiceInk.app"; \
		echo "Copying VoiceInk.app to $$DESTINATION..."; \
		mkdir -p "$(APP_OUTPUT_DIR)"; \
		rm -rf "$$DESTINATION"; \
		ditto "$$APP_PATH" "$$DESTINATION"; \
		xattr -cr "$$DESTINATION"; \
		echo ""; \
		echo "Build complete! App saved to: $$DESTINATION"; \
		echo ""; \
		echo "Limitations of local builds:"; \
		echo "  - No automatic updates (pull new code and rebuild to update)"; \
	else \
		echo "Error: Could not find built VoiceInk.app at $$APP_PATH"; \
		exit 1; \
	fi

# Package an existing app into a DMG (no build, no signing).
package-dmg:
	@./scripts/package-dmg.sh "$(APP_OUTPUT_DIR)/VoiceInk.app"

# Build, Developer ID sign, notarize, and package a DMG for personal use.
personal-dmg:
	@./scripts/build-personal-dmg.sh

# Run application
run:
	@if [ -d "$$HOME/Downloads/$(RUN_APP_NAME).app" ]; then \
		echo "Opening ~/Downloads/$(RUN_APP_NAME).app..."; \
		open "$$HOME/Downloads/$(RUN_APP_NAME).app"; \
	else \
		echo "Looking for $(RUN_APP_NAME).app in DerivedData..."; \
		APP_PATH=$$(find "$$HOME/Library/Developer/Xcode/DerivedData" -name "$(RUN_APP_NAME).app" -type d | head -1) && \
		if [ -n "$$APP_PATH" ]; then \
			echo "Found app at: $$APP_PATH"; \
			open "$$APP_PATH"; \
		else \
			echo "$(RUN_APP_NAME).app not found. Build it with 'make local' or use 'make dev' for the development app."; \
			exit 1; \
		fi; \
	fi

# Build a signed, notarized DMG and matching local Sparkle Appcast.
release: whisper
	@if [ -n "$(NOTES)" ]; then \
		./scripts/release.sh --notes "$(NOTES)" $(RELEASE_ARGS); \
	else \
		./scripts/release.sh $(RELEASE_ARGS); \
	fi

# Store Apple's notarization credentials securely in Keychain.
release-setup:
	@./scripts/setup-release-notarization.sh

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
	@echo "  build              Build the VoiceInk Xcode project"
	@echo "  local              Build locally with automatic Apple Development signing"
	@echo "    LOCAL_CODESIGN_IDENTITY=<SHA or name> selects a signing identity"
	@echo "    APP_OUTPUT_DIR=<directory> selects where the built app is copied"
	@echo "  run                Launch the built VoiceInk app"
	@echo "  dev                Build and run the app (for development)"
	@echo "  release            Build DMG and Appcast using release-notes/<version>.html"
	@echo "  release-setup      Store notarization credentials in Keychain"
	@echo "  all                Run full build process (default)"
	@echo "  clean              Remove build artifacts"
	@echo "  help               Show this help message"
