#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
CHECK_APP="$PWD/build/QuilloReadingCheck.app"
mkdir -p "$CHECK_APP/Contents/MacOS" build/module-cache
APP_SOURCES=(Sources/*.swift)
APP_SOURCES=(${APP_SOURCES:#Sources/Main.swift})
xcrun swiftc -swift-version 5 -parse-as-library -O -target arm64-apple-macos15.0 -module-cache-path build/module-cache $APP_SOURCES Tests/CaptionReadingPreview.swift -o "$CHECK_APP/Contents/MacOS/QuilloReadingCheck" -framework AppKit -framework SwiftUI -framework Speech -framework AVFoundation -framework Translation -framework ScreenCaptureKit -framework Vision -framework CoreImage -framework NaturalLanguage
cat > "$CHECK_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>QuilloReadingCheck</string>
<key>CFBundleIdentifier</key><string>jp.xuhan.QuilloReadingCheck</string>
<key>CFBundleExecutable</key><string>QuilloReadingCheck</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
</dict></plist>
PLIST
codesign --force --sign - "$CHECK_APP"
print "$CHECK_APP"
