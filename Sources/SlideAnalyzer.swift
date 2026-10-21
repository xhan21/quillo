import AppKit
import Vision

struct SlideAnalysis {
    let blocks: [SlideTextBlock]
    let allTextRects: [CGRect]
    var occupancy: SlideOccupancy
    var regionCount = 1
    var regionSources: [SlideRegionSource] {
        (0..<regionCount).map { index in
            SlideRegionSource(number: index + 1, text: blocks.filter { $0.regionNumber == index + 1 }.map(\.text).joined(separator: "\n\n"))
        }
    }
    var signature: String {
        "regions:\(regionCount)\n" + blocks.map { "\($0.regionNumber)|\($0.text)|\(Int($0.rect.minX / 4)),\(Int($0.rect.minY / 4)),\(Int($0.rect.width / 4))" }.joined(separator: "\n")
    }
}

enum SlideAnalyzer {
    static func analyze(image: CGImage, size: CGSize, language: CaptionLanguage, ignored: [CGRect], regions: [CGRect]? = nil, order: SlideReadingOrder = .rows, buildOccupancy: Bool = true) throws -> SlideAnalysis {
        var lines: [(String, CGRect)] = []
        var allRects: [CGRect] = []
        if buildOccupancy || regions == nil {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = [language.ocrLocale]
            request.usesLanguageCorrection = true
            request.minimumTextHeight = 0.008
            try VNImageRequestHandler(cgImage: image).perform([request])
            for observation in request.results ?? [] {
                guard let candidate = observation.topCandidates(1).first, candidate.confidence >= 0.25 else { continue }
                let rect = SlideCoordinates.visionRect(observation.boundingBox, size: size)
                guard !ignored.contains(where: { $0.intersects(rect) }) else { continue }
                allRects.append(rect)
                let text = captionText(candidate.string)
                guard shouldTranslate(text, language: language) else { continue }
                lines.append((text, rect))
            }
        }
        lines.sort { abs($0.1.minY - $1.1.minY) < min($0.1.height, $1.1.height) * 0.4 ? $0.1.minX < $1.1.minX : $0.1.minY < $1.1.minY }
        // Merge adjacent lines within a paragraph, preserving separated columns.
        var merged: [(String, CGRect, CGRect)] = []
        for (text, rect) in lines {
            if let i = merged.indices.reversed().first(where: {
                let last = merged[$0].2
                return abs(last.minX - rect.minX) < max(18, rect.height) && rect.minY >= last.maxY - 3 && rect.minY - last.maxY < max(12, rect.height * 0.65) && abs(last.height - rect.height) < rect.height * 0.35 && merged[$0].0.count < 500
            }) {
                merged[i].0 += language == .english ? " " + text : text
                merged[i].1 = merged[i].1.union(rect); merged[i].2 = rect
            } else { merged.append((text, rect, rect)) }
        }
        var occupancy = buildOccupancy ? SlideSpaceAnalyzer.map(image: image, size: size) : SlideOccupancy(size: size)
        // Ignore our translated cards when examining pixels, then protect all
        // visible original text and the control/live-caption windows separately.
        for rect in ignored { occupancy.mark(rect, occupied: false) }
        for rect in allRects { occupancy.mark(rect.insetBy(dx: -8, dy: -8)) }
        let blocks: [SlideTextBlock]
        if let regions {
            // Crop each selected area before recognition so a browser toolbar or
            // adjacent column cannot be joined to its text by the OCR engine.
            var selected: [SlideTextBlock] = []
            let pixels = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            for (index, normalized) in regions.enumerated() {
                let crop = SlideRegionGeometry.absolute(normalized, in: pixels).integral.intersection(pixels)
                guard !crop.isNull, crop.width > 1, crop.height > 1, let subimage = image.cropping(to: crop) else { continue }
                let points = CGRect(x: crop.minX / pixels.width * size.width, y: crop.minY / pixels.height * size.height, width: crop.width / pixels.width * size.width, height: crop.height / pixels.height * size.height)
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate; request.recognitionLanguages = [language.ocrLocale]
                request.usesLanguageCorrection = true; request.minimumTextHeight = 0.005
                try VNImageRequestHandler(cgImage: subimage).perform([request])
                var regionLines: [SlideTextBlock] = []
                for observation in request.results ?? [] {
                    guard let candidate = observation.topCandidates(1).first, candidate.confidence >= 0.25 else { continue }
                    let rect = SlideCoordinates.visionRect(observation.boundingBox, size: points.size).offsetBy(dx: points.minX, dy: points.minY)
                    let text = captionText(candidate.string)
                    guard !ignored.contains(where: { $0.intersects(rect) }), shouldTranslate(text, language: language) else { continue }
                    regionLines.append(SlideTextBlock(id: regionLines.count, text: text, rect: rect))
                    occupancy.mark(rect.insetBy(dx: -8, dy: -8))
                }
                let sorted = SlideTextOrdering.ordered(paragraphs(regionLines, language: language), mode: order)
                for block in sorted {
                    selected.append(SlideTextBlock(id: selected.count, text: block.text, rect: block.rect, regionNumber: index + 1))
                }
            }
            blocks = selected
        } else {
            blocks = merged.enumerated().map { SlideTextBlock(id: $0.offset, text: $0.element.0, rect: $0.element.1) }
        }
        return SlideAnalysis(blocks: blocks, allTextRects: allRects, occupancy: occupancy, regionCount: regions?.count ?? 1)
    }
    static func paragraphs(_ lines: [SlideTextBlock], language: CaptionLanguage) -> [SlideTextBlock] {
        let ordered = lines.sorted { $0.rect.minY == $1.rect.minY ? $0.rect.minX < $1.rect.minX : $0.rect.minY < $1.rect.minY }
        var groups: [(text: String, rect: CGRect, last: CGRect)] = []
        for line in ordered {
            let bullet = line.text.range(of: #"^[•・●○▪\-]|^[0-9]+[.)、]"#, options: .regularExpression) != nil
            if !bullet, let i = groups.indices.reversed().first(where: {
                let last = groups[$0].last
                return abs(last.minX - line.rect.minX) < max(12, line.rect.height * 0.6)
                    && line.rect.minY >= last.maxY - 3 && line.rect.minY - last.maxY < max(10, line.rect.height * 0.65)
                    && abs(last.height - line.rect.height) < line.rect.height * 0.3
            }) {
                groups[i].text += language == .english ? " " + line.text : line.text
                groups[i].rect = groups[i].rect.union(line.rect); groups[i].last = line.rect
            } else { groups.append((line.text, line.rect, line.rect)) }
        }
        return groups.enumerated().map { SlideTextBlock(id: $0.offset, text: $0.element.text, rect: $0.element.rect) }
    }
    static func shouldTranslate(_ text: String, language: CaptionLanguage) -> Bool {
        let scalars = text.unicodeScalars
        let cjk = scalars.contains { (0x3040...0x30ff).contains(Int($0.value)) || (0x3400...0x9fff).contains(Int($0.value)) }
        switch language {
        case .japanese, .chinese, .traditionalChinese: return cjk
        case .english: return !cjk && scalars.filter { CharacterSet.letters.contains($0) }.count >= 2
        }
    }
}
