# Define a directory for dependencies in the user's home folder
DEPS_DIR := $(HOME)/VoiceInk-Dependencies
WHISPER_CPP_DIR := $(DEPS_DIR)/whisper.cpp
FRAMEWORK_PATH := $(WHISPER_CPP_DIR)/build-apple/whisper.xcframework
LOCAL_DERIVED_DATA := $(CURDIR)/.local-build

# The mlx-swift dependency ships a CudaBuild package plugin. Xcode blocks it on a clean build
# pending a one-time "Trust & Enable" click in the GUI, which fails any command-line build with
# `Validate plug-in "CudaBuild" in package "mlx-swift"`. These flags accept the dependencies the
# checked-in Package.resolved already pins.
PACKAGE_VALIDATION_FLAGS := -skipPackagePluginValidation -skipMacroValidation

# Prefer the stable self-signed identity created by scripts/make-local-signing-cert.sh. Ad-hoc
# signing changes on every build, which makes macOS treat each rebuild as a new app and drop its
# Accessibility / Screen Recording grants. Falls back to ad-hoc when the identity is absent.
LOCAL_SIGN_IDENTITY := $(shell security find-identity -v -p codesigning 2>/dev/null \
	| grep -q "VoiceInk Local Dev" && echo "VoiceInk Local Dev" || echo "-")

.PHONY: all clean whisper setup build local local-cert test check healthcheck help dev run release release-setup

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
	xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Debug \
		$(PACKAGE_VALIDATION_FLAGS) CODE_SIGN_IDENTITY="" build

# Unit tests. Signs the same way `local` does — the test host is the real app bundle, so it
# needs entitlements that do not demand a provisioning profile.
test: setup
	xcodebuild test -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Debug \
		-derivedDataPath "$(LOCAL_DERIVED_DATA)" \
		-xcconfig LocalBuild.xcconfig \
		-destination 'platform=macOS,arch=arm64' \
		-only-testing:VoiceInkTests \
		$(PACKAGE_VALIDATION_FLAGS) \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGNING_ALLOWED=YES \
		DEVELOPMENT_TEAM="" \
		CODE_SIGN_STYLE=Manual \
		PROVISIONING_PROFILE_SPECIFIER="" \
		CODE_SIGN_ENTITLEMENTS="$(CURDIR)/VoiceInk/VoiceInk.local.entitlements" \
		SWIFT_ACTIVE_COMPILATION_CONDITIONS='$$(inherited) LOCAL_BUILD'

# One-time setup: a stable self-signed identity so macOS keeps privacy grants across rebuilds
local-cert:
	@./scripts/make-local-signing-cert.sh

# Build for local use without Apple Developer certificate
local: check setup
	@echo "Building VoiceInk for local use (no Apple Developer certificate required)..."
	@if [ "$(LOCAL_SIGN_IDENTITY)" = "-" ]; then \
		echo "Signing: ad-hoc (macOS will drop privacy permissions on every rebuild)"; \
		echo "         Run ./scripts/make-local-signing-cert.sh once to make them stick."; \
	else \
		echo "Signing: $(LOCAL_SIGN_IDENTITY) (stable — privacy permissions survive rebuilds)"; \
	fi
	@rm -rf "$(LOCAL_DERIVED_DATA)"
	xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Debug \
		-derivedDataPath "$(LOCAL_DERIVED_DATA)" \
		-xcconfig LocalBuild.xcconfig \
		$(PACKAGE_VALIDATION_FLAGS) \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGNING_ALLOWED=YES \
		DEVELOPMENT_TEAM="" \
		CODE_SIGN_ENTITLEMENTS="$(CURDIR)/VoiceInk/VoiceInk.local.entitlements" \
		SWIFT_ACTIVE_COMPILATION_CONDITIONS='$$(inherited) LOCAL_BUILD' \
		build
	@APP_PATH="$(LOCAL_DERIVED_DATA)/Build/Products/Debug/VoiceInk.app" && \
	if [ -d "$$APP_PATH" ] && [ "$(LOCAL_SIGN_IDENTITY)" != "-" ]; then \
		echo "Re-signing with '$(LOCAL_SIGN_IDENTITY)' for a stable signature..."; \
		codesign --force --deep --sign "$(LOCAL_SIGN_IDENTITY)" --options runtime \
			--entitlements "$(CURDIR)/VoiceInk/VoiceInk.local.entitlements" "$$APP_PATH" || exit 1; \
		codesign --verify --deep --strict "$$APP_PATH" || exit 1; \
	fi
	@APP_PATH="$(LOCAL_DERIVED_DATA)/Build/Products/Debug/VoiceInk.app" && \
	if [ -d "$$APP_PATH" ]; then \
		echo "Copying VoiceInk.app to ~/Downloads..."; \
		rm -rf "$$HOME/Downloads/VoiceInk.app"; \
		ditto "$$APP_PATH" "$$HOME/Downloads/VoiceInk.app"; \
		xattr -cr "$$HOME/Downloads/VoiceInk.app"; \
		echo ""; \
		echo "Build complete! App saved to: ~/Downloads/VoiceInk.app"; \
		echo "Run with: open ~/Downloads/VoiceInk.app"; \
		echo ""; \
		echo "Limitations of local builds:"; \
		echo "  - No iCloud dictionary sync"; \
		echo "  - No automatic updates (pull new code and rebuild to update)"; \
	else \
		echo "Error: Could not find built VoiceInk.app at $$APP_PATH"; \
		exit 1; \
	fi

# Run application
run:
	@if [ -d "$$HOME/Downloads/VoiceInk.app" ]; then \
		echo "Opening ~/Downloads/VoiceInk.app..."; \
		open "$$HOME/Downloads/VoiceInk.app"; \
	else \
		echo "Looking for VoiceInk.app in DerivedData..."; \
		APP_PATH=$$(find "$$HOME/Library/Developer/Xcode/DerivedData" -name "VoiceInk.app" -type d | head -1) && \
		if [ -n "$$APP_PATH" ]; then \
			echo "Found app at: $$APP_PATH"; \
			open "$$APP_PATH"; \
		else \
			echo "VoiceInk.app not found. Please run 'make build' or 'make local' first."; \
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
	@echo "  local              Build for local use (no Apple Developer certificate needed)"
	@echo "  test               Run the unit test suite"
	@echo "  run                Launch the built VoiceInk app"
	@echo "  dev                Build and run the app (for development)"
	@echo "  release            Build DMG and Appcast using release-notes/<version>.html"
	@echo "  release-setup      Store notarization credentials in Keychain"
	@echo "  all                Run full build process (default)"
	@echo "  clean              Remove build artifacts"
	@echo "  help               Show this help message"
