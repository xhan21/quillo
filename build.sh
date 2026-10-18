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
codesign --force --sign - --identifier jp.xuhan.KotobaLocal --entitlements Resources/Entitlements.plist "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"
print "$APP_PATH"
