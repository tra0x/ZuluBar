.PHONY: build test clean release zip dmg run help build-free build-free-release build-paid build-paid-release zip-free

# Variables
APP_NAME = ZuluBar
BUILD_DIR = build
SCHEME = ZuluBar
PROJECT = ZuluBar.xcodeproj
DATE = $(shell date +%Y%m%d-%H%M%S)

# Build configurations
CONFIG_DEBUG_FREE = Debug-Free
CONFIG_RELEASE_FREE = Release-Free
CONFIG_DEBUG_PAID = Debug-Paid
CONFIG_RELEASE_PAID = Release-Paid
DERIVED_DATA_PATH = $(BUILD_DIR)/DerivedDataLocal

# Code signing — override in .signing.local.mk (gitignored), e.g.:
#   CODESIGN_IDENTITY = "Developer ID Application: Your Name (TEAMID)"
#   TEAM_ID = TEAMID
CODESIGN_IDENTITY = "Developer ID Application: Your Name (TEAMID)"
TEAM_ID = TEAMID
-include .signing.local.mk

# Default target - show help
help:
	@echo "╔══════════════════════════════════════════════════════════╗"
	@echo "║  ZuluBar - Available Make Commands                  ║"
	@echo "╚══════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "  Development:"
	@echo "    make build               Build debug free version (default)"
	@echo "    make build-free          Build debug free version (unsigned)"
	@echo "    make build-paid          Build debug paid version (signed dev)"
	@echo "    make build-free-release  Build release free (unsigned)"
	@echo "    make build-paid-release  Build release paid (signed)"
	@echo "    make release             Build release paid version (alias)"
	@echo "    make test                Run all tests"
	@echo "    make run                 Build and launch the app"
	@echo "    make clean               Clean all build artifacts"
	@echo ""
	@echo "  Distribution:"
	@echo "    make zip                 Create paid build ZIP (signed)"
	@echo "    make zip-free            Create free build ZIP (unsigned)"
	@echo "    make dmg                 Create DMG disk image (paid)"
	@echo ""
	@echo "  Quick Commands:"
	@echo "    make                     Show this help"
	@echo ""

# Build debug version (defaults to free)
build: build-free

# Build release version (defaults to paid for distribution)
release: build-paid-release

# Free builds
build-free:
	@echo "→ Building Debug-Free (unsigned)..."
	@xcodebuild -project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration $(CONFIG_DEBUG_FREE) \
		CONFIGURATION_BUILD_DIR=$(BUILD_DIR)/Debug-Free \
		build
	@echo "✓ Built: $(BUILD_DIR)/Debug-Free/$(APP_NAME).app"

build-free-release:
	@echo "→ Building Release-Free (unsigned)..."
	@xcodebuild -project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration $(CONFIG_RELEASE_FREE) \
		CONFIGURATION_BUILD_DIR=$(BUILD_DIR)/Release-Free \
		build
	@echo "✓ Built: $(BUILD_DIR)/Release-Free/$(APP_NAME).app"

# Paid builds
build-paid:
	@echo "→ Building Debug-Paid (signed for development)..."
	@xcodebuild -project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration $(CONFIG_DEBUG_PAID) \
		CONFIGURATION_BUILD_DIR=$(BUILD_DIR)/Debug-Paid \
		CODE_SIGN_IDENTITY=$(CODESIGN_IDENTITY) \
		DEVELOPMENT_TEAM=$(TEAM_ID) \
		build
	@echo "✓ Built: $(BUILD_DIR)/Debug-Paid/$(APP_NAME).app"

build-paid-release:
	@echo "→ Building Release-Paid (signed for distribution)..."
	@xcodebuild -project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration $(CONFIG_RELEASE_PAID) \
		CONFIGURATION_BUILD_DIR=$(BUILD_DIR)/Release-Paid \
		CODE_SIGN_IDENTITY=$(CODESIGN_IDENTITY) \
		DEVELOPMENT_TEAM=$(TEAM_ID) \
		build
	@echo "✓ Built: $(BUILD_DIR)/Release-Paid/$(APP_NAME).app"

# Run tests
test:
	@echo "→ Running tests..."
	@xcodebuild test \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration $(CONFIG_DEBUG_FREE) \
		-derivedDataPath $(DERIVED_DATA_PATH) \
		CODE_SIGNING_ALLOWED=NO

# Create ZIP for free build
zip-free: build-free-release
	@echo "→ Creating ZIP archive (free build)..."
	@cd $(BUILD_DIR)/Release-Free && \
		zip -r $(APP_NAME)-Free-$(DATE).zip $(APP_NAME).app
	@echo "✓ Created: $(BUILD_DIR)/Release-Free/$(APP_NAME)-Free-$(DATE).zip"
	@ls -lh $(BUILD_DIR)/Release-Free/$(APP_NAME)-Free-$(DATE).zip | awk '{print "  Size: " $$5}'

# Create ZIP for paid build (for distribution)
zip: build-paid-release
	@echo "→ Creating ZIP archive (paid build)..."
	@cd $(BUILD_DIR)/Release-Paid && \
		zip -r $(APP_NAME)-$(DATE).zip $(APP_NAME).app
	@echo "✓ Created: $(BUILD_DIR)/Release-Paid/$(APP_NAME)-$(DATE).zip"
	@ls -lh $(BUILD_DIR)/Release-Paid/$(APP_NAME)-$(DATE).zip | awk '{print "  Size: " $$5}'

# Create DMG disk image (builds paid release first)
dmg: build-paid-release
	@echo "→ Creating DMG disk image..."
	@hdiutil create \
		-volname "$(APP_NAME)" \
		-srcfolder $(BUILD_DIR)/Release-Paid/$(APP_NAME).app \
		-ov \
		-format UDZO \
		$(BUILD_DIR)/$(APP_NAME)-$(DATE).dmg
	@echo "✓ Created: $(BUILD_DIR)/$(APP_NAME)-$(DATE).dmg"
	@ls -lh $(BUILD_DIR)/$(APP_NAME)-$(DATE).dmg | awk '{print "  Size: " $$5}'

# Build and run the app
run: build
	@echo "→ Launching $(APP_NAME)..."
	@open $(BUILD_DIR)/Debug-Free/$(APP_NAME).app

# Clean all build artifacts
clean:
	@echo "→ Cleaning build artifacts..."
	@rm -rf $(BUILD_DIR)
	@xcodebuild clean -project $(PROJECT) -scheme $(SCHEME) > /dev/null 2>&1
	@echo "✓ Cleaned"
