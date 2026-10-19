import AppKit

// Keep the most recent complete layout lines on screen, without a timed page
// queue or a manual scrollbar. The model and transcript retain the full text.
enum CaptionViewport {
    static func latest(source: String, translation: String, showsSource: Bool, showsTranslation: Bool,
                       style: CaptionAppearance, width: Double, height: Double) -> (source: String, translation: String) {
        let (sl, tl) = lineBudget(showsSource: showsSource, showsTranslation: showsTranslation, style: style, height: height)
        return (tail(source, size: style.sourceFontSize, width: width - 60, lines: sl, weight: .medium),
                tail(translation, size: style.translationFontSize, width: width - 60, lines: tl, weight: .regular))
    }

    static func lineBudget(showsSource: Bool, showsTranslation: Bool, style: CaptionAppearance, height: Double) -> (Int, Int) {
        let sh = CaptionTypesetting.lineHeight(style.sourceFontSize, weight: .medium)
        let th = CaptionTypesetting.lineHeight(style.translationFontSize)
        var sl = showsSource ? 1 : 0, tl = showsTranslation ? 1 : 0
        var remaining = max(1, height - 76) - Double(sl) * sh - Double(tl) * th
        while true {
            let canSource = sl > 0 && remaining >= sh
            let canTarget = tl > 0 && remaining >= th
            if !canSource && !canTarget { break }
            if canSource && (!canTarget || sl <= tl) { sl += 1; remaining -= sh }
            else { tl += 1; remaining -= th }
        }
        return (sl, tl)
    }

    static func tail(_ text: String, size: Double, width: Double, lines: Int, weight: NSFont.Weight) -> String {
        guard !text.isEmpty, lines > 0 else { return "" }
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 5
        let storage = NSTextStorage(string: text, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .paragraphStyle: paragraph])
        let manager = NSLayoutManager()
        let container = NSTextContainer(containerSize: NSSize(width: max(1, width), height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        storage.addLayoutManager(manager); manager.addTextContainer(container)
        let glyphs = manager.glyphRange(for: container)
        var ranges: [NSRange] = []
        manager.enumerateLineFragments(forGlyphRange: glyphs) { _, _, _, range, _ in
            ranges.append(manager.characterRange(forGlyphRange: range, actualGlyphRange: nil))
        }
        guard ranges.count > lines else { return text }
        let start = ranges[ranges.count - lines].location
        let suffix = (text as NSString).substring(from: start)
        if CaptionTypesetting.lineCount(suffix, size: size, width: max(1, width), weight: weight) <= lines { return suffix }
        // Rewrapping a line extracted from the paragraph can change its layout.
        // Find a fitting grapheme-safe suffix in that case.
        let characters = Array(suffix)
        var low = 1, high = characters.count, fit = 1
        while low <= high {
            let mid = (low + high) / 2
            if CaptionTypesetting.lineCount(String(characters.suffix(mid)), size: size, width: max(1, width), weight: weight) <= lines {
                fit = mid; low = mid + 1
            } else { high = mid - 1 }
        }
        return String(characters.suffix(fit))
    }
}
