#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p build/module-cache
SWIFT=(xcrun swiftc -swift-version 5 -parse-as-library -O -module-cache-path build/module-cache)
$SWIFT Sources/CaptionSupport.swift Tests/CoreTests.swift -o build/core-tests
build/core-tests
$SWIFT Sources/CaptionSupport.swift Sources/CaptionAppearance.swift Tests/AppearanceTests.swift -o build/appearance-tests
build/appearance-tests
$SWIFT Sources/CaptionSupport.swift Sources/CaptionAppearance.swift Sources/CaptionPlayback.swift Sources/CaptionPaginator.swift Tests/PlaybackTests.swift -o build/playback-tests
build/playback-tests
$SWIFT Sources/CaptionSupport.swift Sources/CaptionAppearance.swift Sources/CaptionPaginator.swift Sources/EnglishCaptionReading.swift Tests/EnglishCaptionReadingTests.swift -o build/english-reading-tests -framework AppKit -framework NaturalLanguage
build/english-reading-tests
$SWIFT Sources/CaptionSupport.swift Sources/SlideLayout.swift Sources/SlidePanelLayout.swift Sources/SlidePanelPresentation.swift Tests/SlidePanelTests.swift -o build/slide-panel-tests -framework AppKit
build/slide-panel-tests
$SWIFT Sources/CaptionSupport.swift Sources/MaterialGlossary.swift Sources/SlideLayout.swift Sources/SlidePanelLayout.swift Sources/SlideSummary.swift Tests/SlideSummaryTests.swift -o build/slide-summary-tests -framework AppKit
build/slide-summary-tests
$SWIFT Sources/CaptionSupport.swift Sources/SlideLayout.swift Sources/SlideReadingOrder.swift Sources/SlideAnalyzer.swift Sources/SlideAnnotationRenderer.swift Sources/SlideDemo.swift Tests/SlideTests.swift -o build/slide-tests -framework AppKit -framework Vision
build/slide-tests
$SWIFT Sources/CaptionSupport.swift Sources/SlideLayout.swift Sources/SlideReadingOrder.swift Sources/SlideRegionEditing.swift Sources/SlideRegionSelection.swift Tests/SlideRegionEditingTests.swift -o build/slide-region-tests -framework AppKit
build/slide-region-tests
APP_SOURCES=(Sources/*.swift)
APP_SOURCES=(${APP_SOURCES:#Sources/Main.swift})
$SWIFT $APP_SOURCES Tests/PlaybackIntegrationTests.swift -o build/playback-integration-tests -framework AppKit -framework SwiftUI -framework Speech -framework AVFoundation -framework Translation -framework ScreenCaptureKit -framework Vision -framework CoreImage
build/playback-integration-tests
$SWIFT $APP_SOURCES Tests/GlossaryTests.swift -o build/glossary-tests -framework AppKit -framework SwiftUI -framework Speech -framework AVFoundation -framework Translation -framework ScreenCaptureKit -framework Vision -framework CoreImage
build/glossary-tests
$SWIFT $APP_SOURCES Tests/LanguageCoverageTests.swift -o build/language-coverage-tests -framework AppKit -framework SwiftUI -framework Speech -framework AVFoundation -framework Translation -framework ScreenCaptureKit -framework Vision -framework CoreImage
build/language-coverage-tests
