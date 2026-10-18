import AppKit

@main enum SlideTests {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let size = CGSize(width: 1000, height: 650)
        let canvas = SlideDemoCanvas(frame: CGRect(origin: .zero, size: size), language: .japanese)
        guard let rep = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds) else { fatalError() }
        canvas.cacheDisplay(in: canvas.bounds, to: rep)
        let image = rep.cgImage!
        let result = try SlideAnalyzer.analyze(image: image, size: size, language: .japanese, ignored: [])
        precondition(result.blocks.contains { $0.text.contains("情報の流れ") }, "Recognize the sample title")
        precondition(result.blocks.contains { $0.text.contains("入力") })
        let figure = CGRect(x: 710, y: 180, width: 220, height: 300)
        precondition(!result.occupancy.isFree(CGRect(x: 730, y: 200, width: 50, height: 50)), "Solid graphics are occupied, not blank")
        let translations = result.blocks.map { SlideTranslation(id: $0.id, source: $0, text: "Translated text appears near the original. This is a sample sentence.") }
        let began = ContinuousClock.now
        let placement = SlidePlacement.annotations(for: translations, occupancy: result.occupancy, fontSize: 14)
        precondition(!placement.placed.isEmpty)
        for annotation in placement.placed {
            precondition(!annotation.rect.intersects(figure), "Must avoid graphics")
            precondition(!result.allTextRects.contains { $0.intersects(annotation.rect) }, "Must avoid original text")
            precondition(!placement.placed.contains { $0.id != annotation.id && $0.rect.intersects(annotation.rect) })
        }
        var packed = SlideOccupancy(size: size); packed.mark(CGRect(origin: .zero, size: size))
        let full = SlidePlacement.annotations(for: translations, occupancy: packed, fontSize: 22)
        precondition(full.placed.isEmpty && full.overflow.count == translations.count, "Dense slides must fall back without covering content")
        let display = CGRect(x: -1440, y: 120, width: 1440, height: 880)
        let window = CGRect(x: -1080, y: 330, width: 720, height: 460)
        var denseSource = SlideOccupancy(size: window.size)
        denseSource.mark(CGRect(origin: .zero, size: window.size))
        let paragraphs: [SlideTranslation] = (0..<16).map { i in
            let rect = CGRect(x: Double(35 + (i % 2) * 350), y: Double(20 + (i / 2) * 52), width: 300, height: 22)
            let block = SlideTextBlock(id: i, text: "Original \(i)", rect: rect)
            return SlideTranslation(id: i, source: block, text: "Translation \(i): every paragraph stays visible outside a dense slide.")
        }
        let outsideSpace = SlidePlacementSpace(source: denseSource, sourceFrame: window, availableFrame: display)
        precondition(outsideSpace.sourceRect == CGRect(x: 360, y: 210, width: 720, height: 460), "Map negative-screen origins and top-left coordinates")
        let outside = SlidePlacement.annotations(for: outsideSpace.translations(paragraphs), occupancy: outsideSpace.occupancy, fontSize: 14, sourceBounds: outsideSpace.sourceRect)
        precondition(outside.placed.count == 16 && outside.overflow.isEmpty, "All 16 dense-slide paragraphs must fit in the display margins")
        for card in outside.placed {
            precondition(!card.rect.intersects(outsideSpace.sourceRect), "Never cover dense source material")
            precondition(CGRect(origin: .zero, size: display.size).contains(card.rect), "Never place beyond the display")
            precondition(card.sourceRect != nil, "External translations retain their original anchor")
            precondition(!outside.placed.contains { $0.id != card.id && $0.rect.intersects(card.rect) })
            precondition(card.text == paragraphs[card.id].text, "External cards retain the complete translation")
        }
        let translatedWindow = window.offsetBy(dx: 80, dy: -40)
        let movedSpace = SlidePlacementSpace(source: denseSource, sourceFrame: translatedWindow, availableFrame: display)
        precondition(movedSpace.translations(paragraphs)[0].source.rect == outsideSpace.translations(paragraphs)[0].source.rect.offsetBy(dx: 80, dy: 40), "Anchors follow window moves")
        let occupiedSidebar = CGRect(x: display.minX, y: display.minY, width: 320, height: display.height)
        let reservedSpace = SlidePlacementSpace(source: denseSource, sourceFrame: window, availableFrame: display, protectedFrames: [occupiedSidebar])
        let reserved = SlidePlacement.annotations(for: reservedSpace.translations(paragraphs), occupancy: reservedSpace.occupancy, fontSize: 14, sourceBounds: reservedSpace.sourceRect)
        precondition(reserved.placed.allSatisfy { !$0.rect.intersects(CGRect(x: 0, y: 0, width: 320, height: display.height)) }, "External cards avoid the control/live-caption windows")
        let fullscreenSpace = SlidePlacementSpace(source: denseSource, sourceFrame: window, availableFrame: window)
        let fullscreen = SlidePlacement.annotations(for: fullscreenSpace.translations(paragraphs), occupancy: fullscreenSpace.occupancy, fontSize: 14, sourceBounds: fullscreenSpace.sourceRect)
        precondition(fullscreen.placed.isEmpty && fullscreen.overflow.count == 16, "No exterior space must retain full translations in the list")
        let longText = String(repeating: "Long translated sentences must remain complete. ", count: 300)
        let longItem = SlideTranslation(id: 500, source: result.blocks[0], text: longText)
        let longResult = SlidePlacement.annotations(for: [longItem], occupancy: result.occupancy, fontSize: 22)
        precondition(longResult.placed.isEmpty && longResult.overflow.first?.text == longText, "Oversized translations retain their full text in the list")
        var protected = result.occupancy
        let control = CGRect(x: 0, y: 0, width: 650, height: 450)
        protected.mark(control)
        let withControl = SlidePlacement.annotations(for: translations, occupancy: protected, fontSize: 14)
        precondition(withControl.placed.allSatisfy { !$0.rect.intersects(control) }, "Our control panel must not be covered")
        let topLeft = SlideCoordinates.visionRect(CGRect(x: 0.1, y: 0.8, width: 0.3, height: 0.1), size: size)
        precondition(abs(topLeft.minY - 65) < 0.01)
        let secondDisplay = SlideCoordinates.appKitFrame(quartz: CGRect(x: -1200, y: -300, width: 1200, height: 800), primaryHeight: 900)
        precondition(secondDisplay == CGRect(x: -1200, y: 400, width: 1200, height: 800))
        precondition(SlideAnalyzer.shouldTranslate("待ち行列", language: .japanese))
        precondition(!SlideAnalyzer.shouldTranslate("queue", language: .japanese))
        precondition(SlideAnalyzer.shouldTranslate("A queue of tasks", language: .english))
        precondition(!SlideAnalyzer.shouldTranslate("123 / 456", language: .english))
        let masked = try SlideAnalyzer.analyze(image: image, size: size, language: .japanese, ignored: result.allTextRects)
        precondition(masked.blocks.isEmpty, "Ignore existing overlay/control text")
        let firstRegion = CGRect(x: 0.04, y: 0.27, width: 0.60, height: 0.16)
        let secondRegion = CGRect(x: 0.04, y: 0.55, width: 0.60, height: 0.18)
        let cropped = try SlideAnalyzer.analyze(image: image, size: size, language: .japanese, ignored: [], regions: [firstRegion])
        precondition(cropped.blocks.count == 1 && cropped.blocks[0].text.contains("入力"))
        precondition(!cropped.blocks.contains { $0.text.contains("情報の流れ") || $0.text.contains("処理した結果") }, "Outside text must not reach translation")
        let panelOCR = try SlideAnalyzer.analyze(image: image, size: size, language: .japanese, ignored: [], regions: [firstRegion], buildOccupancy: false)
        precondition(panelOCR.blocks.map(\.text) == cropped.blocks.map(\.text) && panelOCR.allTextRects.isEmpty, "Separate panel OCR reads only selected crops")
        let multiple = try SlideAnalyzer.analyze(image: image, size: size, language: .japanese, ignored: [], regions: [firstRegion, secondRegion])
        precondition(multiple.blocks.count == 2 && multiple.blocks[1].text.contains("処理した結果"))
        let croppedPlacement = SlidePlacement.annotations(for: cropped.blocks.map { SlideTranslation(id: $0.id, source: $0, text: "The computer processes the information.") }, occupancy: cropped.occupancy, fontSize: 14)
        precondition(!croppedPlacement.placed.isEmpty, "Placement searches the whole window, not only the selected rectangle")
        let normalized = SlideRegionGeometry.normalized(CGRect(x: 30, y: 60, width: 100, height: 80), in: CGRect(x: 10, y: 20, width: 200, height: 160))!
        precondition(normalized == CGRect(x: 0.1, y: 0.25, width: 0.5, height: 0.5))
        precondition(SlideRegionGeometry.absolute(normalized, in: CGRect(x: 0, y: 0, width: 400, height: 320)) == CGRect(x: 40, y: 80, width: 200, height: 160))
        func block(_ id: Int, _ x: Double, _ y: Double, _ width: Double) -> SlideTextBlock { .init(id: id, text: "Block \(id)", rect: CGRect(x: x, y: y, width: width, height: 25)) }
        let columns = [block(0, 40, 20, 800), block(1, 40, 100, 300), block(2, 40, 190, 300), block(3, 500, 100, 300), block(4, 500, 190, 300), block(5, 40, 290, 800)]
        precondition(SlideTextOrdering.ordered(columns, mode: .rows).map(\.id) == [0, 1, 3, 2, 4, 5])
        precondition(SlideTextOrdering.ordered(columns, mode: .columns).map(\.id) == [0, 1, 2, 3, 4, 5], "Spanning title, left column, right column, footer")
        let traditional = SlideDemoCanvas(frame: CGRect(origin: .zero, size: size), language: .traditionalChinese)
        let traditionalRep = traditional.bitmapImageRepForCachingDisplay(in: traditional.bounds)!
        traditional.cacheDisplay(in: traditional.bounds, to: traditionalRep)
        let traditionalOCR = try SlideAnalyzer.analyze(image: traditionalRep.cgImage!, size: size, language: .traditionalChinese, ignored: [], regions: [firstRegion])
        precondition(traditionalOCR.blocks.contains { $0.text.contains("資訊") }, "Traditional Chinese OCR must retain the script")
        precondition(CaptionLanguage.traditionalChinese.rawValue == "zh-Hant" && CaptionLanguage.traditionalChinese.speechLocale == "zh-TW")
        print("PASS: real Vision OCR \(result.blocks.count) blocks, \(placement.placed.count) nearby translations, no text/graphic/card collisions, dense-slide fallback, source-language filtering, coordinate conversion. Layout + dense fallback: \(began.duration(to: .now))")
    }
}
