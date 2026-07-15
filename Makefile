APP_NAME ?= CodexUsageMonitor
BUNDLE_IDENTIFIER ?= local.codex.usagemonitor
VERSION ?= 0.4.3
BUILD_NUMBER ?= 7
MINIMUM_MACOS := 13.0
ROOT := $(abspath ../..)
DEFAULT_OUT_DIR := $(ROOT)/outputs
FALLBACK_OUT_DIR := $(abspath ..)
ifneq ($(wildcard $(DEFAULT_OUT_DIR)),)
OUT_DIR ?= $(DEFAULT_OUT_DIR)
else
OUT_DIR ?= $(FALLBACK_OUT_DIR)
endif
APP := $(OUT_DIR)/$(APP_NAME).app
MACOS_DIR := $(APP)/Contents/MacOS
RESOURCES_DIR := $(APP)/Contents/Resources
EXECUTABLE := $(MACOS_DIR)/$(APP_NAME)
RELEASE_ZIP_NAME := $(APP_NAME)-$(VERSION).zip
RELEASE_DMG_NAME := $(APP_NAME)-$(VERSION).dmg
ZIP_SHA256_NAME := $(RELEASE_ZIP_NAME).sha256
DMG_SHA256_NAME := $(RELEASE_DMG_NAME).sha256
MANIFEST_NAME := $(APP_NAME)-$(VERSION).manifest.json
SOURCE_ARCHIVE_NAME := $(APP_NAME)-$(VERSION)-source.zip
SOURCE_ARCHIVE_SHA256_NAME := $(SOURCE_ARCHIVE_NAME).sha256
RELEASE_ZIP := $(OUT_DIR)/$(RELEASE_ZIP_NAME)
RELEASE_DMG := $(OUT_DIR)/$(RELEASE_DMG_NAME)
ZIP_SHA256 := $(OUT_DIR)/$(ZIP_SHA256_NAME)
DMG_SHA256 := $(OUT_DIR)/$(DMG_SHA256_NAME)
MANIFEST := $(OUT_DIR)/$(MANIFEST_NAME)
SOURCE_ARCHIVE := $(OUT_DIR)/$(SOURCE_ARCHIVE_NAME)
SOURCE_ARCHIVE_SHA256 := $(OUT_DIR)/$(SOURCE_ARCHIVE_SHA256_NAME)
BUILD_DIR := build
DMG_STAGING := $(BUILD_DIR)/dmg
PREPARED_INFO_PLIST := $(BUILD_DIR)/Info.plist
ARM64_EXECUTABLE := $(BUILD_DIR)/$(APP_NAME)-arm64
X86_64_EXECUTABLE := $(BUILD_DIR)/$(APP_NAME)-x86_64
ARM64_MODULE_CACHE := $(BUILD_DIR)/ModuleCache-arm64
X86_64_MODULE_CACHE := $(BUILD_DIR)/ModuleCache-x86_64
DIAG_MODULE_CACHE := $(BUILD_DIR)/ModuleCache-diagnose
TEST_MODULE_CACHE := $(BUILD_DIR)/ModuleCache-tests
RUNTIME_MODULE_CACHE := $(BUILD_DIR)/ModuleCache-runtime
CONCURRENCY_MODULE_CACHE := $(BUILD_DIR)/ModuleCache-concurrency
APP_ICON := Resources/AppIcon.icns
MENU_BAR_ICON := Resources/MenuBarIcon.png
SOURCES := $(wildcard Sources/*.swift)
BUNDLE_RESOURCES := $(APP_ICON) $(MENU_BAR_ICON) Resources/PrivacyInfo.xcprivacy
PRIVACY_MANIFEST := Resources/PrivacyInfo.xcprivacy
ENTITLEMENTS := Resources/Release.entitlements
DATA_SOURCES := Sources/UsageData.swift
TEST_DATA_SOURCES := Sources/UsageData.swift Sources/AppSettings.swift
DIAGNOSTIC := $(BUILD_DIR)/DumpSummary
DIAGNOSTIC_CACHE := $(BUILD_DIR)/diagnostic-usage-cache.json
TEST_RUNNER := $(BUILD_DIR)/RunTests
RUNTIME_VERIFIER := $(BUILD_DIR)/VerifyRuntimePanel
RELEASE_TOOL_TESTS := Tools/RunReleaseToolTests.py
RELEASE_VERSION_VALIDATOR := Tools/ValidateReleaseVersion.py
PUBLIC_SOURCE_VALIDATOR := Tools/ValidatePublicSource.py
DMG_VERIFIER := Tools/VerifyDiskImage.py
DEMO_OUT ?= $(BUILD_DIR)/demo-codex-home
SIGN_IDENTITY ?= -
NOTARY_PROFILE ?=
NOTARY_KEYCHAIN ?=
SIGNATURE_POLICY ?= any

.PHONY: all clean run diagnose demo-data verify-runtime verify-concurrency release release-signed release-notarized release-dmg-notarized release-manifest publish-preflight verify-release verify-public-release verify-public-source audit-public-history source-archive verify-source-archive verify-app verify-privacy verify-version verify-artifacts verify-public-artifacts verify-manifest verify-public-manifest package dmg package-dmg checksum-zip checksum-dmg checksum-source assets check test sign sign-developer-id sign-dmg notarize notarize-dmg staple staple-dmg prepare-info-plist require-clean-repo require-public-bundle-identifier require-sign-identity require-notary-profile print-version print-build

all: $(EXECUTABLE)

assets: $(APP_ICON) $(MENU_BAR_ICON)

$(APP_ICON) $(MENU_BAR_ICON): Tools/MakeAppIcon.py
	python3 Tools/MakeAppIcon.py

prepare-info-plist: Info.plist Makefile
	mkdir -p "$(BUILD_DIR)"
	cp Info.plist "$(PREPARED_INFO_PLIST)"
	/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $(APP_NAME)" "$(PREPARED_INFO_PLIST)"
	/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $(BUNDLE_IDENTIFIER)" "$(PREPARED_INFO_PLIST)"
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(VERSION)" "$(PREPARED_INFO_PLIST)"
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(BUILD_NUMBER)" "$(PREPARED_INFO_PLIST)"
	/usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion $(MINIMUM_MACOS)" "$(PREPARED_INFO_PLIST)"

$(EXECUTABLE): prepare-info-plist $(SOURCES) Info.plist Makefile $(BUNDLE_RESOURCES) $(APP_ICON)
	mkdir -p "$(MACOS_DIR)"
	rm -rf "$(RESOURCES_DIR)"
	mkdir -p "$(RESOURCES_DIR)"
	mkdir -p "$(ARM64_MODULE_CACHE)"
	mkdir -p "$(X86_64_MODULE_CACHE)"
	cp "$(PREPARED_INFO_PLIST)" "$(APP)/Contents/Info.plist"
	cp $(BUNDLE_RESOURCES) "$(RESOURCES_DIR)/"
	printf "APPL????" > "$(APP)/Contents/PkgInfo"
	xcrun swiftc -O -target arm64-apple-macosx13.0 -module-cache-path "$(ARM64_MODULE_CACHE)" $(SOURCES) -o "$(ARM64_EXECUTABLE)" -framework AppKit -framework SwiftUI -framework Combine -framework ServiceManagement -framework UserNotifications
	xcrun swiftc -O -target x86_64-apple-macosx13.0 -module-cache-path "$(X86_64_MODULE_CACHE)" $(SOURCES) -o "$(X86_64_EXECUTABLE)" -framework AppKit -framework SwiftUI -framework Combine -framework ServiceManagement -framework UserNotifications
	xcrun lipo -create -output "$(EXECUTABLE)" "$(ARM64_EXECUTABLE)" "$(X86_64_EXECUTABLE)"
	chmod +x "$(EXECUTABLE)"
	codesign --force --deep --sign - "$(APP)"

run: all
	open "$(APP)"

demo-data:
	python3 Tools/MakeDemoFixture.py --out "$(DEMO_OUT)" --replace

verify-runtime: all $(RUNTIME_VERIFIER)
	"$(RUNTIME_VERIFIER)" "$(APP)"

$(RUNTIME_VERIFIER): Tools/VerifyRuntimePanel.swift
	mkdir -p "$(BUILD_DIR)"
	mkdir -p "$(RUNTIME_MODULE_CACHE)"
	xcrun swiftc -O -module-cache-path "$(RUNTIME_MODULE_CACHE)" Tools/VerifyRuntimePanel.swift -o "$(RUNTIME_VERIFIER)" -framework AppKit -framework Carbon -framework CoreGraphics

release: all
	$(MAKE) package

release-signed: all sign-developer-id
	$(MAKE) package

release-notarized: release-signed notarize staple
	$(MAKE) package

release-dmg-notarized: require-clean-repo require-public-bundle-identifier require-sign-identity require-notary-profile
	$(MAKE) publish-preflight
	$(MAKE) release-notarized
	$(MAKE) package-dmg
	$(MAKE) sign-dmg
	$(MAKE) notarize-dmg
	$(MAKE) staple-dmg
	$(MAKE) checksum-dmg
	$(MAKE) release-manifest SIGNATURE_POLICY=developer-id
	$(MAKE) verify-public-artifacts SIGNATURE_POLICY=developer-id

release-manifest:
	python3 Tools/MakeReleaseManifest.py --repo "$(CURDIR)" --app "$(APP)" --zip "$(RELEASE_ZIP)" --dmg "$(RELEASE_DMG)" --out "$(MANIFEST)" --app-name "$(APP_NAME)" --bundle-identifier "$(BUNDLE_IDENTIFIER)" --version "$(VERSION)" --build "$(BUILD_NUMBER)" --minimum-macos "$(MINIMUM_MACOS)" --signature-policy "$(SIGNATURE_POLICY)"

publish-preflight: all require-clean-repo require-public-bundle-identifier require-sign-identity require-notary-profile verify-public-source
	python3 Tools/ReleasePreflight.py --app-name "$(APP_NAME)" --sign-identity "$(SIGN_IDENTITY)" --notary-profile "$(NOTARY_PROFILE)" $(if $(NOTARY_KEYCHAIN),--notary-keychain "$(NOTARY_KEYCHAIN)",) --bundle-identifier "$(BUNDLE_IDENTIFIER)" --app "$(APP)" --entitlements "$(ENTITLEMENTS)" --version "$(VERSION)" --build "$(BUILD_NUMBER)" --minimum-macos "$(MINIMUM_MACOS)" $(if $(CHECK_NOTARY),--check-notary-network,)

verify-release: check release dmg
	$(MAKE) release-manifest
	$(MAKE) verify-artifacts

verify-public-release: require-clean-repo require-public-bundle-identifier verify-public-source verify-release
	$(MAKE) verify-public-artifacts

verify-public-source:
	python3 "$(PUBLIC_SOURCE_VALIDATOR)" --repo "$(CURDIR)"

audit-public-history:
	python3 "$(PUBLIC_SOURCE_VALIDATOR)" --repo "$(CURDIR)" --check-history

source-archive: require-clean-repo verify-public-source
	mkdir -p "$(OUT_DIR)"
	rm -f "$(SOURCE_ARCHIVE)" "$(SOURCE_ARCHIVE_SHA256)"
	git archive --format=zip --prefix="$(APP_NAME)-$(VERSION)/" --output="$(SOURCE_ARCHIVE)" HEAD
	$(MAKE) checksum-source
	$(MAKE) verify-source-archive

checksum-source:
	cd "$(OUT_DIR)" && shasum -a 256 "$(SOURCE_ARCHIVE_NAME)" > "$(SOURCE_ARCHIVE_SHA256_NAME)"

verify-source-archive:
	test -f "$(SOURCE_ARCHIVE)"
	test -f "$(SOURCE_ARCHIVE_SHA256)"
	cd "$(OUT_DIR)" && shasum -a 256 -c "$(SOURCE_ARCHIVE_SHA256_NAME)"
	python3 "$(PUBLIC_SOURCE_VALIDATOR)" --repo "$(CURDIR)" --archive "$(SOURCE_ARCHIVE)" --archive-prefix "$(APP_NAME)-$(VERSION)"

sign: all
	codesign --force --deep --sign "$(SIGN_IDENTITY)" "$(APP)"

package: all
	rm -f "$(RELEASE_ZIP)" "$(ZIP_SHA256)"
	ditto -c -k --norsrc --keepParent "$(APP)" "$(RELEASE_ZIP)"
	$(MAKE) checksum-zip
	@echo "$(RELEASE_ZIP)"

dmg: all package-dmg

package-dmg: all
	rm -rf "$(DMG_STAGING)"
	mkdir -p "$(DMG_STAGING)"
	ditto "$(APP)" "$(DMG_STAGING)/$(APP_NAME).app"
	ln -s /Applications "$(DMG_STAGING)/Applications"
	rm -f "$(RELEASE_DMG)" "$(DMG_SHA256)"
	hdiutil create -volname "Codex Usage Monitor" -srcfolder "$(DMG_STAGING)" -ov -format UDZO "$(RELEASE_DMG)"
	$(MAKE) checksum-dmg
	@echo "$(RELEASE_DMG)"

checksum-zip:
	cd "$(OUT_DIR)" && shasum -a 256 "$(RELEASE_ZIP_NAME)" > "$(ZIP_SHA256_NAME)"

checksum-dmg:
	cd "$(OUT_DIR)" && shasum -a 256 "$(RELEASE_DMG_NAME)" > "$(DMG_SHA256_NAME)"

sign-developer-id: require-sign-identity all
	codesign --force --deep --options runtime --timestamp --entitlements "$(ENTITLEMENTS)" --sign "$(SIGN_IDENTITY)" "$(APP)"
	codesign --verify --deep --strict --verbose=2 "$(APP)"

sign-dmg: require-sign-identity
	codesign --force --timestamp --sign "$(SIGN_IDENTITY)" "$(RELEASE_DMG)"
	codesign --verify --verbose=2 "$(RELEASE_DMG)"

notarize: require-notary-profile
	xcrun notarytool submit "$(RELEASE_ZIP)" --keychain-profile "$(NOTARY_PROFILE)" $(if $(NOTARY_KEYCHAIN),--keychain "$(NOTARY_KEYCHAIN)",) --wait

notarize-dmg: require-notary-profile
	xcrun notarytool submit "$(RELEASE_DMG)" --keychain-profile "$(NOTARY_PROFILE)" $(if $(NOTARY_KEYCHAIN),--keychain "$(NOTARY_KEYCHAIN)",) --wait

staple:
	xcrun stapler staple "$(APP)"
	xcrun stapler validate "$(APP)"

staple-dmg:
	xcrun stapler staple "$(RELEASE_DMG)"
	xcrun stapler validate "$(RELEASE_DMG)"

require-sign-identity:
	@if [ "$(SIGN_IDENTITY)" = "-" ]; then echo "Set SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)'"; exit 2; fi

require-notary-profile:
	@if [ -z "$(NOTARY_PROFILE)" ]; then echo "Set NOTARY_PROFILE to an xcrun notarytool keychain profile"; exit 2; fi

require-clean-repo:
	@if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then echo "Public release verification requires a git repository."; exit 2; fi
	@if [ -n "$$(git status --short)" ]; then echo "Working tree is dirty; commit or stash changes before a public release."; git status --short; exit 2; fi

require-public-bundle-identifier:
	@python3 Tools/ValidateBundleIdentifier.py "$(BUNDLE_IDENTIFIER)"

check: verify-version verify-concurrency all test diagnose verify-app

verify-concurrency:
	mkdir -p "$(CONCURRENCY_MODULE_CACHE)"
	xcrun swiftc -typecheck -O -target arm64-apple-macosx13.0 -module-cache-path "$(CONCURRENCY_MODULE_CACHE)" $(SOURCES) -framework AppKit -framework SwiftUI -framework Combine -framework ServiceManagement -framework UserNotifications
	xcrun swiftc -typecheck -target arm64-apple-macosx13.0 -module-cache-path "$(CONCURRENCY_MODULE_CACHE)" -warn-concurrency -strict-concurrency=complete -warnings-as-errors $(SOURCES) -framework AppKit -framework SwiftUI -framework Combine -framework ServiceManagement -framework UserNotifications
	xcrun swiftc -typecheck -target arm64-apple-macosx13.0 -module-cache-path "$(CONCURRENCY_MODULE_CACHE)" -warn-concurrency -strict-concurrency=complete -warnings-as-errors $(TEST_DATA_SOURCES) Tools/RunTests.swift -framework SwiftUI -framework Combine -framework ServiceManagement
	xcrun swiftc -typecheck -target arm64-apple-macosx13.0 -module-cache-path "$(CONCURRENCY_MODULE_CACHE)" -warn-concurrency -strict-concurrency=complete -warnings-as-errors $(DATA_SOURCES) Tools/DumpSummary.swift -framework SwiftUI -framework Combine

verify-version:
	python3 "$(RELEASE_VERSION_VALIDATOR)" --repo "$(CURDIR)"

print-version:
	@printf '%s\n' "$(VERSION)"

print-build:
	@printf '%s\n' "$(BUILD_NUMBER)"

verify-app: all
	test "$$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$(APP)/Contents/Info.plist")" = "$(BUNDLE_IDENTIFIER)"
	test "$$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$(APP)/Contents/Info.plist")" = "$(VERSION)"
	test "$$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$(APP)/Contents/Info.plist")" = "$(BUILD_NUMBER)"
	test "$$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$(APP)/Contents/Info.plist")" = "$(MINIMUM_MACOS)"
	test "$$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$(APP)/Contents/Info.plist")" = "true"
	plutil -lint "$(APP)/Contents/Info.plist" "$(PRIVACY_MANIFEST)"
	plutil -lint "$(ENTITLEMENTS)"
	test -f "$(APP)/Contents/Resources/AppIcon.icns"
	test -f "$(APP)/Contents/Resources/MenuBarIcon.png"
	test -f "$(APP)/Contents/Resources/PrivacyInfo.xcprivacy"
	test "$$(sips -g pixelWidth "$(APP)/Contents/Resources/AppIcon.icns" | awk '/pixelWidth/ { print $$2 }')" = "1024"
	test "$$(sips -g pixelHeight "$(APP)/Contents/Resources/AppIcon.icns" | awk '/pixelHeight/ { print $$2 }')" = "1024"
	test "$$(sips -g pixelWidth "$(APP)/Contents/Resources/MenuBarIcon.png" | awk '/pixelWidth/ { print $$2 }')" = "36"
	test "$$(sips -g pixelHeight "$(APP)/Contents/Resources/MenuBarIcon.png" | awk '/pixelHeight/ { print $$2 }')" = "36"
	python3 Tools/ValidatePrivacyManifest.py "$(PRIVACY_MANIFEST)" "$(APP)/Contents/Resources/PrivacyInfo.xcprivacy"
	xcrun lipo "$(EXECUTABLE)" -verify_arch arm64 x86_64
	codesign --verify --deep --strict --verbose=2 "$(APP)"

verify-privacy: all
	python3 Tools/ValidatePrivacyManifest.py "$(PRIVACY_MANIFEST)" "$(APP)/Contents/Resources/PrivacyInfo.xcprivacy"

verify-artifacts:
	test -f "$(RELEASE_ZIP)"
	test -f "$(ZIP_SHA256)"
	test -f "$(RELEASE_DMG)"
	test -f "$(DMG_SHA256)"
	test -f "$(MANIFEST)"
	cd "$(OUT_DIR)" && shasum -a 256 -c "$(ZIP_SHA256_NAME)"
	cd "$(OUT_DIR)" && shasum -a 256 -c "$(DMG_SHA256_NAME)"
	python3 "$(DMG_VERIFIER)" "$(RELEASE_DMG)"
	$(MAKE) verify-manifest

verify-public-artifacts: require-clean-repo verify-artifacts
	$(MAKE) verify-public-manifest

verify-manifest:
	python3 Tools/MakeReleaseManifest.py --repo "$(CURDIR)" --app "$(APP)" --zip "$(RELEASE_ZIP)" --dmg "$(RELEASE_DMG)" --out "$(MANIFEST)" --app-name "$(APP_NAME)" --bundle-identifier "$(BUNDLE_IDENTIFIER)" --version "$(VERSION)" --build "$(BUILD_NUMBER)" --minimum-macos "$(MINIMUM_MACOS)" --signature-policy "$(SIGNATURE_POLICY)" --verify

verify-public-manifest:
	python3 Tools/MakeReleaseManifest.py --repo "$(CURDIR)" --app "$(APP)" --zip "$(RELEASE_ZIP)" --dmg "$(RELEASE_DMG)" --out "$(MANIFEST)" --app-name "$(APP_NAME)" --bundle-identifier "$(BUNDLE_IDENTIFIER)" --version "$(VERSION)" --build "$(BUILD_NUMBER)" --minimum-macos "$(MINIMUM_MACOS)" --signature-policy "$(SIGNATURE_POLICY)" --verify --strict-repo --require-clean

test: $(TEST_RUNNER) $(RELEASE_TOOL_TESTS)
	"$(TEST_RUNNER)"
	python3 "$(RELEASE_TOOL_TESTS)"

diagnose: $(DIAGNOSTIC)
	"$(DIAGNOSTIC)" "$(abspath $(DIAGNOSTIC_CACHE))"

$(TEST_RUNNER): $(TEST_DATA_SOURCES) Tools/RunTests.swift
	mkdir -p "build"
	mkdir -p "$(TEST_MODULE_CACHE)"
	xcrun swiftc -O -target arm64-apple-macosx13.0 -module-cache-path "$(TEST_MODULE_CACHE)" $(TEST_DATA_SOURCES) Tools/RunTests.swift -o "$(TEST_RUNNER)" -framework SwiftUI -framework Combine -framework ServiceManagement

$(DIAGNOSTIC): $(DATA_SOURCES) Tools/DumpSummary.swift
	mkdir -p "build"
	mkdir -p "$(DIAG_MODULE_CACHE)"
	xcrun swiftc -O -target arm64-apple-macosx13.0 -module-cache-path "$(DIAG_MODULE_CACHE)" $(DATA_SOURCES) Tools/DumpSummary.swift -o "$(DIAGNOSTIC)" -framework SwiftUI -framework Combine

clean:
	rm -rf "$(APP)" "$(RELEASE_ZIP)" "$(RELEASE_DMG)" "$(ZIP_SHA256)" "$(DMG_SHA256)" "$(MANIFEST)" "$(SOURCE_ARCHIVE)" "$(SOURCE_ARCHIVE_SHA256)" "$(BUILD_DIR)"
