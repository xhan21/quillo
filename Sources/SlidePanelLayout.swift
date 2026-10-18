import AppKit
import CryptoKit

struct SlidePanelPage: Equatable {
    let text: String
    let start: Int // Character offset, retained when resizing or more results arrive.
    let end: Int
}
struct SlidePanelLayout {
    let fontSize: Double
    let pages: [SlidePanelPage]
}

enum SlidePanelTypesetting {
    static let minimumFontSize = 12.0
    static func attributes(fontSize: Double) -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = fontSize * 0.28
        style.paragraphSpacing = fontSize * 0.45
        style.lineBreakMode = .byWordWrapping
        return [.font: NSFont.systemFont(ofSize: fontSize), .paragraphStyle: style,
                .foregroundColor: NSColor(calibratedRed: 0.10, green: 0.20, blue: 0.17, alpha: 1)]
    }
    static func measuredHeight(_ text: String, fontSize: Double, width: Double) -> Double {
        let storage = NSTextStorage(string: text, attributes: attributes(fontSize: fontSize))
        let manager = NSLayoutManager()
        let container = NSTextContainer(containerSize: CGSize(width: max(1, width), height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        storage.addLayoutManager(manager); manager.addTextContainer(container)
        manager.ensureLayout(for: container)
        return ceil(manager.usedRect(for: container).height)
    }
    static func fit(_ text: String, size: CGSize, preferredFontSize: Double) -> SlidePanelLayout {
        let maximum = clamp(preferredFontSize, minimumFontSize, 32)
        let width = max(40, size.width), height = max(40, size.height)
        guard !text.isEmpty else { return .init(fontSize: maximum, pages: []) }
        for font in stride(from: maximum, through: minimumFontSize, by: -1) {
            if measuredHeight(text, fontSize: font, width: width) <= height - 4 {
                return .init(fontSize: font, pages: [.init(text: text, start: 0, end: text.count)])
            }
        }
        // Grapheme-safe pages keep every character; never truncate or shrink below 12 pt.
        let chars = Array(text)
        var pages: [SlidePanelPage] = [], start = 0
        while start < chars.count {
            var low = 1, high = chars.count - start, count = 1
            while low <= high {
                let middle = (low + high) / 2
                if measuredHeight(String(chars[start..<(start + middle)]), fontSize: minimumFontSize, width: width) <= height - 4 {
                    count = middle; low = middle + 1
                } else { high = middle - 1 }
            }
            if start + count < chars.count, count > 12 {
                let floor = start + max(1, Int(Double(count) * 0.6))
                if let boundary = (floor..<(start + count)).reversed().first(where: { chars[$0].isWhitespace || "。！？.!?".contains(chars[$0]) }) {
                    count = boundary - start + 1
                }
            }
            pages.append(.init(text: String(chars[start..<(start + count)]), start: start, end: start + count))
            start += count
        }
        return .init(fontSize: minimumFontSize, pages: pages)
    }
    static func displayDuration(_ text: String) -> Double { clamp(Double(text.count) / 12 + 3, 8, 28) }
    static func listParts(_ text: String) -> (marker: String, body: String) {
        let regex = try! NSRegularExpression(pattern: #"^(\s*(?:[•●○▪・]|[0-9]+[.)、]|[A-Za-z][.)]|-\s)\s*)(.+)$"#, options: .dotMatchesLineSeparators)
        let value = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: value.length)) else { return ("", text) }
        return (value.substring(with: match.range(at: 1)), value.substring(with: match.range(at: 2)))
    }
    static func pageKey(document: String, blocks: [SlideTextBlock]) -> String {
        guard !blocks.isEmpty else { return "" }
        let texts = blocks.map { $0.text.split(whereSeparator: \.isWhitespace).joined(separator: " ") }.sorted()
        let data = try! JSONEncoder().encode([document] + texts)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
