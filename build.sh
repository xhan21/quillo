#!/bin/zsh
set -euo pipefail
SCRIPT_DIR="${0:A:h}"
cd "$SCRIPT_DIR"
mkdir -p build/module-cache
APP_PATH="$SCRIPT_DIR/build/Quillo.app"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
SDK_PATH="$(xcrun --show-sdk-path)"
xcrun swiftc -swift-version 5 -parse-as-library -O -target arm64-apple-macos15.0 -sdk "$SDK_PATH" -module-cache-path "$SCRIPT_DIR/build/module-cache" Sources/*.swift -o "$APP_PATH/Contents/MacOS/KotobaLocal" -framework AppKit -framework SwiftUI -framework Speech -framework AVFoundation -framework Translation -framework Carbon -framework ScreenCaptureKit -framework Vision -framework CoreImage
cp Resources/ClassMaterialTranslator-LICENSE.txt "$APP_PATH/Contents/Resources/"
cp Resources/Info.plist "$APP_PATH/Contents/Info.plist"
if [[ -f Resources/AppIcon.icns ]]; then cp Resources/AppIcon.icns "$APP_PATH/Contents/Resources/AppIcon.icns"; fi
# Keep the signing identity across local updates so macOS can retain consent.
# An explicit identity takes precedence; never silently fall back if configured.
SIGNING_FILE="$HOME/Library/Application Support/Quillo/Signing/identity.sha1"
SIGNING_IDENTITY="${QUILLO_SIGNING_IDENTITY:-}"
if [[ -z "$SIGNING_IDENTITY" && -f "$SIGNING_FILE" ]]; then
    SIGNING_IDENTITY="$(cat "$SIGNING_FILE")"
    if [[ ! "$SIGNING_IDENTITY" =~ '^[A-Fa-f0-9]{40}$' ]]; then
        print -u2 "Invalid Quillo signing identity. Check $SIGNING_FILE"; exit 1
    fi
fi
if [[ -z "$SIGNING_IDENTITY" ]]; then
    SIGNING_IDENTITY="-"
    print -u2 "Ad-hoc signing: permissions may be requested again after updates. See docs/SETUP.md."
fi
codesign --force --sign "$SIGNING_IDENTITY" --identifier jp.xuhan.KotobaLocal --entitlements Resources/Entitlements.plist "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"
print "$APP_PATH"
