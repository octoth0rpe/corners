DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
export DEVELOPER_DIR

BUILD_DIR := build
INSTALL_DIR := $(HOME)/Applications
# A self-signed certificate in the login keychain, made by `make cert`.
SIGN_IDENTITY := Corners Local Signing
# An explicit destination stops xcodebuild warning that "My Mac" matches
# both arm64 and x86_64. Builds are for this Mac's architecture only, which
# is all a local install needs; an App Store archive builds both.
XCODEBUILD := xcodebuild -project Corners.xcodeproj -scheme Corners -derivedDataPath $(BUILD_DIR) \
	-destination 'platform=macOS,arch=$(shell uname -m)'

.DEFAULT_GOAL := build
.PHONY: project build release run install test cert clean

project: Corners.xcodeproj

Corners.xcodeproj: project.yml
	xcodegen generate

# Debug build into build/
build: project
	$(XCODEBUILD) -configuration Debug build

release: project
	$(XCODEBUILD) -configuration Release build

# Unit tests (CornersTests)
test: project
	$(XCODEBUILD) test

# Debug build, launched from build/
run: build
	@pkill -x Corners || true
	open $(BUILD_DIR)/Build/Products/Debug/Corners.app

# Release build, installed to ~/Applications and relaunched.
#
# macOS ties the Accessibility grant to the code signature. Ad-hoc signatures
# change with every build, so the installed copy is re-signed with the stable
# local identity when it exists. Without it, expect to re-grant Accessibility
# after each install.
install: release
	@pkill -x Corners || true
	rm -rf "$(INSTALL_DIR)/Corners.app"
	mkdir -p "$(INSTALL_DIR)"
	ditto $(BUILD_DIR)/Build/Products/Release/Corners.app "$(INSTALL_DIR)/Corners.app"
	@if security find-certificate -c "$(SIGN_IDENTITY)" >/dev/null 2>&1; then \
		codesign --force --sign "$(SIGN_IDENTITY)" \
			--preserve-metadata=entitlements,flags,runtime "$(INSTALL_DIR)/Corners.app"; \
	else \
		echo "warning: no \"$(SIGN_IDENTITY)\" certificate; run 'make cert' so Accessibility" \
			"permission survives reinstalls."; \
	fi
	open "$(INSTALL_DIR)/Corners.app"

# One-time: create the self-signed code signing certificate used by `make install`.
cert:
	scripts/make-signing-cert.sh "$(SIGN_IDENTITY)"

clean:
	rm -rf $(BUILD_DIR) Corners.xcodeproj
