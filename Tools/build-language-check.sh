#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
mkdir -p build/module-cache
CHECK_APP="$PWD/build/QuilloLanguageCheck.app"
mkdir -p "$CHECK_APP/Contents/MacOS"
APP_SOURCES=(Sources/*.swift)
APP_SOURCES=(${APP_SOURCES:#Sources/Main.swift})
xcrun swiftc -swift-version 5 -parse-as-library -O -target arm64-apple-macos15.0 -module-cache-path build/module-cache $APP_SOURCES Tests/LanguageMatrixApp.swift -o "$CHECK_APP/Contents/MacOS/QuilloLanguageCheck" -framework AppKit -framework SwiftUI -framework Speech -framework AVFoundation -framework Translation -framework ScreenCaptureKit -framework Vision -framework CoreImage
cat > "$CHECK_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>QuilloLanguageCheck</string>
<key>CFBundleIdentifier</key><string>jp.xuhan.QuilloLanguageCheck</string>
<key>CFBundleExecutable</key><string>QuilloLanguageCheck</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
</dict></plist>
PLIST
codesign --force --sign - "$CHECK_APP"
print "$CHECK_APP"
