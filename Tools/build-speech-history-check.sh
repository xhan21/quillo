#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
CHECK_APP="$PWD/build/QuilloSpeechHistoryCheck.app"
mkdir -p "$CHECK_APP/Contents/MacOS" "$CHECK_APP/Contents/Resources" build/module-cache
say -v Kyoko -r 165 -o "$CHECK_APP/Contents/Resources/history-speech-fixture.aiff" '[[slnc 4000]] 最初に身近な道具を観察します。 [[slnc 1300]] 次に簡単な試作品を作ります。 [[slnc 1300]] 最後に使い心地を比較します。'
APP_SOURCES=(Sources/*.swift)
APP_SOURCES=(${APP_SOURCES:#Sources/Main.swift})
xcrun swiftc -swift-version 5 -parse-as-library -O -target arm64-apple-macos15.0 -module-cache-path build/module-cache $APP_SOURCES Tests/SpeechHistoryPreview.swift -o "$CHECK_APP/Contents/MacOS/QuilloSpeechHistoryCheck" -framework AppKit -framework SwiftUI -framework Speech -framework AVFoundation -framework Translation -framework ScreenCaptureKit -framework Vision -framework CoreImage -framework NaturalLanguage
cat > "$CHECK_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>QuilloSpeechHistoryCheck</string>
<key>CFBundleIdentifier</key><string>jp.xuhan.QuilloSpeechHistoryCheck</string>
<key>CFBundleExecutable</key><string>QuilloSpeechHistoryCheck</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>NSSpeechRecognitionUsageDescription</key><string>合成した確認用音声を端末内で認識します。マイクは使用しません。</string>
</dict></plist>
PLIST
codesign --force --sign - "$CHECK_APP"
print "$CHECK_APP"
