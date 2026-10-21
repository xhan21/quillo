import AppKit

struct SlideTextBlock: Identifiable, Equatable {
    let id: Int
    let text: String
    let rect: CGRect // Top-left origin, in captured-content points.
    var regionNumber: Int = 1
}
struct SlideRegionSource: Equatable {
    let number: Int // Matches the numbered selection rectangle, including empty areas.
    let text: String
    func heading(for language: CaptionLanguage) -> String {
        switch language {
        case .japanese: return "【範囲\(number)】"
        case .english: return "【Area \(number)】"
        case .chinese: return "【区域\(number)】"
        case .traditionalChinese: return "【區域\(number)】"
        }
    }
}
struct SlideTranslation: Identifiable, Equatable {
    let id: Int
    let source: SlideTextBlock
    let text: String
}
struct SlideAnnotation: Identifiable, Equatable {
    let id: Int
    let text: String
    let rect: CGRect
    // Only external cards need a line back to their original paragraph.
    var sourceRect: CGRect? = nil
    func offsetBy(dx: Double, dy: Double) -> SlideAnnotation {
        .init(id: id, text: text, rect: rect.offsetBy(dx: dx, dy: dy), sourceRect: sourceRect?.offsetBy(dx: dx, dy: dy))
    }
}

// OCR coordinates belong to the captured window. The presentation surface can
// cover the containing display without capturing anything outside that window.
struct SlidePlacementSpace {
    let frame: CGRect // AppKit screen coordinates, excluding menu bar and Dock.
    let sourceRect: CGRect // Top-left coordinates within frame.
    var occupancy: SlideOccupancy
    init(source: SlideOccupancy, sourceFrame: CGRect, availableFrame: CGRect, protectedFrames: [CGRect] = []) {
        frame = availableFrame
        sourceRect = SlideCoordinates.localRect(appKit: sourceFrame, contentFrame: availableFrame)
        var map = SlideOccupancy(size: availableFrame.size)
        for y in 0..<source.rows { for x in 0..<source.columns where source.busy[y * source.columns + x] {
            map.mark(CGRect(x: sourceRect.minX + Double(x) * source.cellWidth, y: sourceRect.minY + Double(y) * source.cellHeight, width: source.cellWidth, height: source.cellHeight))
        } }
        for protected in protectedFrames {
            map.mark(SlideCoordinates.localRect(appKit: protected, contentFrame: availableFrame).insetBy(dx: -6, dy: -6))
        }
        occupancy = map
    }
    func translations(_ source: [SlideTranslation]) -> [SlideTranslation] {
        source.map { item in
            .init(id: item.id, source: .init(id: item.source.id, text: item.source.text, rect: item.source.rect.offsetBy(dx: sourceRect.minX, dy: sourceRect.minY)), text: item.text)
        }
    }
}

struct SlideOccupancy {
    let size: CGSize
    let columns: Int
    let rows: Int
    var busy: [Bool]
    var cellWidth: Double { size.width / Double(columns) }
    var cellHeight: Double { size.height / Double(rows) }
    init(size: CGSize, cell: Double = 8) {
        self.size = size
        columns = max(1, Int(ceil(size.width / cell))); rows = max(1, Int(ceil(size.height / cell)))
        busy = Array(repeating: false, count: columns * rows)
    }
    func indices(in rect: CGRect) -> [Int] {
        let r = rect.intersection(CGRect(origin: .zero, size: size))
        guard !r.isNull, r.width > 0, r.height > 0 else { return [] }
        let x0 = max(0, Int(floor(r.minX / cellWidth))), x1 = min(columns - 1, Int(ceil(r.maxX / cellWidth)) - 1)
        let y0 = max(0, Int(floor(r.minY / cellHeight))), y1 = min(rows - 1, Int(ceil(r.maxY / cellHeight)) - 1)
        guard x0 <= x1, y0 <= y1 else { return [] }
        return (y0...y1).flatMap { y in (x0...x1).map { y * columns + $0 } }
    }
    mutating func mark(_ rect: CGRect, occupied: Bool = true) { for i in indices(in: rect) { busy[i] = occupied } }
    func prefixCounts() -> [Int] {
        let stride = columns + 1
        var result = [Int](repeating: 0, count: stride * (rows + 1))
        for y in 0..<rows {
            var row = 0
            for x in 0..<columns {
                row += busy[y * columns + x] ? 1 : 0
                result[(y + 1) * stride + x + 1] = result[y * stride + x + 1] + row
            }
        }
        return result
    }
    func isFree(_ rect: CGRect, prefix: [Int]? = nil) -> Bool {
        guard CGRect(origin: .zero, size: size).insetBy(dx: 7, dy: 7).contains(rect) else { return false }
        guard let prefix else { return !indices(in: rect).contains { busy[$0] } }
        let x0 = max(0, Int(floor(rect.minX / cellWidth))), x1 = min(columns, Int(ceil(rect.maxX / cellWidth)))
        let y0 = max(0, Int(floor(rect.minY / cellHeight))), y1 = min(rows, Int(ceil(rect.maxY / cellHeight)))
        let stride = columns + 1
        return prefix[y1 * stride + x1] - prefix[y0 * stride + x1] - prefix[y1 * stride + x0] + prefix[y0 * stride + x0] == 0
    }
}

// Conservatively treats text, edges, and regions different from the dominant
// slide background as occupied. Photographs and dense slides can leave no slot.
enum SlideSpaceAnalyzer {
    static func map(image: CGImage, size: CGSize) -> SlideOccupancy {
        var map = SlideOccupancy(size: size)
        let w = map.columns * 3, h = map.rows * 3
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h)); return true
        }
        guard rendered else { map.busy = Array(repeating: true, count: map.busy.count); return map }
        var colors: [Int: Int] = [:]
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let key = Int(pixels[i] / 16) * 256 + Int(pixels[i + 1] / 16) * 16 + Int(pixels[i + 2] / 16)
            colors[key, default: 0] += 1
        }
        let background = colors.max { $0.value < $1.value }?.key ?? 0
        let bg = [Double(background / 256) * 16 + 8, Double((background / 16) % 16) * 16 + 8, Double(background % 16) * 16 + 8]
        for y in 0..<map.rows { for x in 0..<map.columns {
            var different = false
            for yy in 0..<3 { for xx in 0..<3 {
                let i = ((y * 3 + yy) * w + x * 3 + xx) * 4
                if (0..<3).contains(where: { abs(Double(pixels[i + $0]) - bg[$0]) > 25 }) { different = true }
            } }
            map.busy[y * map.columns + x] = different
        } }
        return map
    }
}

enum SlidePlacement {
    static func annotations(for translations: [SlideTranslation], occupancy: SlideOccupancy, fontSize: Double, sourceBounds: CGRect? = nil) -> (placed: [SlideAnnotation], overflow: [SlideTranslation]) {
        var map = occupancy
        var placed: [SlideAnnotation] = [], overflow: [SlideTranslation] = []
        for item in translations.sorted(by: { $0.id < $1.id }) {
            let prefix = map.prefixCounts()
            let screen = CGRect(origin: .zero, size: map.size)
            var externalBands: [CGRect] = []
            if let source = sourceBounds?.intersection(screen), !source.isNull {
                externalBands = [
                    CGRect(x: 8, y: 8, width: max(0, source.minX - 20), height: map.size.height - 16),
                    CGRect(x: source.maxX + 12, y: 8, width: max(0, map.size.width - source.maxX - 20), height: map.size.height - 16),
                    CGRect(x: 8, y: 8, width: map.size.width - 16, height: max(0, source.minY - 20)),
                    CGRect(x: 8, y: source.maxY + 12, width: map.size.width - 16, height: max(0, map.size.height - source.maxY - 20))
                ].filter { $0.width >= 120 && $0.height >= 25 }
            }
            let extraWidths = externalBands.map { min(520.0, $0.width - 8) }
            let widths = Array(Set(([min(340, max(180, item.source.rect.width)), 160, 220, 300, 380] + extraWidths).map { min($0, map.size.width - 28) })).sorted()
            var best: (CGRect, CGFloat)?
            for width in widths where width > 40 {
                let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 3
                let bounds = (item.text as NSString).boundingRect(with: NSSize(width: width - 18, height: 10000), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: NSFont.systemFont(ofSize: fontSize), .paragraphStyle: paragraph])
                let height = ceil(bounds.height) + 16
                guard height <= map.size.height - 20 else { continue }
                let anchor = item.source.rect
                var candidates = [
                    CGRect(x: anchor.minX, y: anchor.maxY + 10, width: width, height: height),
                    CGRect(x: anchor.minX, y: anchor.minY - height - 10, width: width, height: height),
                    CGRect(x: anchor.maxX + 12, y: anchor.minY, width: width, height: height),
                    CGRect(x: anchor.minX - width - 12, y: anchor.minY, width: width, height: height)
                ]
                // Also try aligned positions in the outside margins. These do
                // not have the old 300-point cutoff for central paragraphs.
                for band in externalBands where band.width >= width + 8 && band.height >= height + 8 {
                    let x = clamp(anchor.midX - width / 2, band.minX + 4, band.maxX - width)
                    let y = clamp(anchor.midY - height / 2, band.minY + 4, band.maxY - height)
                    candidates.append(CGRect(x: x, y: y, width: width, height: height))
                    for yy in stride(from: band.minY + 4, through: band.maxY - height, by: 12.0) {
                        for xx in stride(from: band.minX + 4, through: band.maxX - width, by: 12.0) {
                            candidates.append(CGRect(x: xx, y: yy, width: width, height: height))
                        }
                    }
                }
                // Search only the nearby area; do not assign a remote translation
                // that students could mistake for a different paragraph.
                let distance = min(300.0, map.size.width * 0.35)
                let step = 12.0
                for y in stride(from: max(8, anchor.midY - distance), through: min(map.size.height - height - 8, anchor.maxY + distance), by: step) {
                    for x in stride(from: max(8, anchor.midX - width - distance), through: min(map.size.width - width - 8, anchor.maxX + distance), by: step) {
                        candidates.append(CGRect(x: x, y: y, width: width, height: height))
                    }
                }
                for rect in candidates where map.isFree(rect.insetBy(dx: -3, dy: -3), prefix: prefix) {
                    let dx = max(0, max(rect.minX - anchor.maxX, anchor.minX - rect.maxX))
                    let dy = max(0, max(rect.minY - anchor.maxY, anchor.minY - rect.maxY))
                    let outside = sourceBounds.map { !rect.intersects($0) } ?? false
                    guard outside || hypot(dx, dy) <= distance else { continue }
                    let score = hypot(dx, dy) * 4 + abs(rect.midX - anchor.midX) * 0.12 + abs(rect.minY - anchor.maxY) * 0.08 + height * 0.1
                    if best == nil || score < best!.1 { best = (rect, score) }
                }
            }
            if let (rect, _) = best {
                let outside = sourceBounds.map { !$0.contains(rect) } ?? false
                map.mark(rect.insetBy(dx: -7, dy: -7)); placed.append(SlideAnnotation(id: item.id, text: item.text, rect: rect, sourceRect: outside ? item.source.rect : nil))
            } else { overflow.append(item) }
        }
        return (placed, overflow)
    }
}

enum SlideCoordinates {
    static func appKitFrame(quartz: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: quartz.minX, y: primaryHeight - quartz.maxY, width: quartz.width, height: quartz.height)
    }
    static func localRect(appKit: CGRect, contentFrame: CGRect) -> CGRect {
        CGRect(x: appKit.minX - contentFrame.minX, y: contentFrame.maxY - appKit.maxY, width: appKit.width, height: appKit.height)
    }
    static func visionRect(_ normalized: CGRect, size: CGSize) -> CGRect {
        CGRect(x: normalized.minX * size.width, y: (1 - normalized.maxY) * size.height, width: normalized.width * size.width, height: normalized.height * size.height)
    }
}
