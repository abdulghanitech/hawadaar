APP := build/Hawadaar.app
# Sign with the "Hawadaar Release Signing" certificate when present, so builds keep the same identity
# and the Keychain doesn't ask again after an update. Falls back to ad-hoc signing.
SIGN_ID := $(or $(shell security find-identity -p codesigning 2>/dev/null | awk '/"Hawadaar Release Signing"/ {print $$2; exit}'),-)
VERSION := $(shell /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)

# With only the Command Line Tools installed, Swift Testing lives outside the default search paths.
CLT_FRAMEWORKS := /Library/Developer/CommandLineTools/Library/Developer/Frameworks
ifeq ($(shell xcode-select -p),/Library/Developer/CommandLineTools)
TEST_FLAGS := --disable-xctest --enable-swift-testing -Xswiftc -F -Xswiftc $(CLT_FRAMEWORKS) \
	-Xlinker -F -Xlinker $(CLT_FRAMEWORKS) -Xlinker -rpath -Xlinker $(CLT_FRAMEWORKS)
endif

.PHONY: app universal run test zip icon clean

## Build Hawadaar.app for this Mac's architecture
app:
	swift build -c release
	$(MAKE) bundle BINARY=.build/release/Hawadaar

## Build a universal (Apple Silicon + Intel) Hawadaar.app
universal:
	swift build -c release --triple arm64-apple-macosx14.0
	swift build -c release --triple x86_64-apple-macosx14.0
	mkdir -p build
	lipo -create -output build/Hawadaar-universal \
		.build/arm64-apple-macosx/release/Hawadaar .build/x86_64-apple-macosx/release/Hawadaar
	$(MAKE) bundle BINARY=build/Hawadaar-universal

bundle:
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp $(BINARY) $(APP)/Contents/MacOS/Hawadaar
	cp Resources/Info.plist $(APP)/Contents/
	cp Resources/AppIcon.icns $(APP)/Contents/Resources/
	codesign --force --sign $(SIGN_ID) $(APP)
	@echo "Built $(APP)"

## Build and launch
run: app
	-pkill -x Hawadaar
	open $(APP)

test:
	swift test $(TEST_FLAGS)

## Universal release zip for GitHub Releases
zip: universal
	cd build && ditto -c -k --keepParent Hawadaar.app Hawadaar-$(VERSION).zip
	@echo "Built build/Hawadaar-$(VERSION).zip"

## Regenerate the app icon
icon:
	swift scripts/make-icon.swift

clean:
	rm -rf .build build
