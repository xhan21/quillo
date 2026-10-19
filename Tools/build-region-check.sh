#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
CHECK_APP="$PWD/build/QuilloRegionCheck.app"
mkdir -p "$CHECK_APP/Contents/MacOS" build/module-cache
xcrun swiftc -swift-version 5 -parse-as-library -O -module-cache-path build/module-cache Sources/CaptionSupport.swift Sources/SlideLayout.swift Sources/SlideReadingOrder.swift Sources/SlideRegionEditing.swift Sources/SlideRegionSelection.swift Sources/SlideDemo.swift Sources/SlideAnnotationRenderer.swift Tests/SlideRegionPreview.swift -o "$CHECK_APP/Contents/MacOS/QuilloRegionCheck" -framework AppKit
cat > "$CHECK_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>QuilloRegionCheck</string>
<key>CFBundleIdentifier</key><string>jp.xuhan.QuilloRegionCheck</string>
<key>CFBundleExecutable</key><string>QuilloRegionCheck</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
</dict></plist>
PLIST
codesign --force --sign - "$CHECK_APP"
print "$CHECK_APP"
