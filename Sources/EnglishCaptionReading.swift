import AppKit
import NaturalLanguage

// Presentation only: never changes translation jobs or the full transcript.
// There is one replaceable pending hypothesis, not a queue of old captions.
struct EnglishCaptionReading {
    static let updateInterval = 0.65
    private(set) var text = ""
    private(set) var previous = ""
    private var latest = ""
    private var pending: String?
    private var lastDisplay = -Double.infinity
    private var previousUntil = 0.0
    private var cue: UUID?
    var nextWakeup: Double? {
        [pending == nil ? nil : lastDisplay + Self.updateInterval,
         previous.isEmpty ? nil : previousUntil].compactMap { $0 }.min()
    }
    mutating func begin(_ id: UUID, now: Double) {
        guard cue != id else { return }
        let completed = EnglishCaptionLayout.sentences(latest).last(where: EnglishCaptionLayout.isComplete) ?? ""
        previous = completed; previousUntil = now + 5
        cue = id; text = ""; latest = ""; pending = nil; lastDisplay = -.infinity
    }
    mutating func receive(_ value: String, now: Double, final: Bool = false) {
        guard !value.isEmpty else { return }
        latest = value
        if value == text { pending = nil; return }
        if text.isEmpty || final || now - lastDisplay >= Self.updateInterval {
            text = value; lastDisplay = now; pending = nil
        } else { pending = value }
    }
    mutating func flush(now: Double) {
        if let pending { text = pending; lastDisplay = now; self.pending = nil }
    }
    mutating func tick(now: Double) {
        if now >= previousUntil { previous = "" }
        if now - lastDisplay >= Self.updateInterval { flush(now: now) }
    }
}

struct EnglishCaptionLayout {
    var text: String
    var previous: String = ""
    var fontSize: Double
    var previousFontSize: Double
    var continued = false
    var height: Double {
        // Measured by layout(), retained as a testable bound on the rendered block.
        measuredHeight
    }
    private var measuredHeight = 0.0

    static func sentences(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.setLanguage(.english); tokenizer.string = text
        return tokenizer.tokens(for: text.startIndex..<text.endIndex)
            .map { captionText(String(text[$0])) }.filter { !$0.isEmpty }
    }
    static func isComplete(_ text: String) -> Bool {
        let end = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'”’)]}")))
        return end.last.map { ".!?".contains($0) } == true
    }
    static func layout(text: String, previous: String, fontSize: Double, width: Double, height: Double) -> Self {
        let parts = sentences(text)
        let current = parts.last ?? ""
        let prior = parts.count > 1 ? parts[parts.count - 2] : previous
        let available = max(1, height), width = max(1, width)
        func measured(_ value: String, _ size: Double) -> Double {
            Double(CaptionTypesetting.lineCount(value, size: size, width: width)) * CaptionTypesetting.lineHeight(size)
        }
        // Preserve the whole current sentence by reducing only its display font,
        // with a 18pt floor (or the user's smaller font). Saved sizes stay intact.
        let minimum = min(fontSize, 18)
        var size = fontSize
        while size > minimum && measured(current, size) > available { size = max(minimum, size - 1) }
        var result = Self(text: current, fontSize: size, previousFontSize: min(size, max(14, size * 0.8)))
        if measured(current, size) > available {
            // Exceptionally long sentences use a clause/word boundary, rather
            // than dropping an arbitrary first line. Never add or rewrite words.
            let lines = max(1, Int(available / CaptionTypesetting.lineHeight(size)))
            let tail = CaptionViewport.tail(current, size: size, width: width, lines: lines, weight: .regular)
            let start = current.index(current.endIndex, offsetBy: -tail.count)
            let boundaries = current.indices.filter { index in
                guard index >= start, index > current.startIndex else { return false }
                let before = current[current.index(before: index)]
                return before.isWhitespace && !current[index].isWhitespace
            }
            let clauses = boundaries.filter { index in
                let prefix = current[..<index].trimmingCharacters(in: .whitespacesAndNewlines)
                return prefix.last.map { ",;:—".contains($0) } == true
            }
            let boundary = clauses.first ?? boundaries.first ?? start
            result.text = String(current[boundary...]); result.continued = boundary > current.startIndex
        }
        result.measuredHeight = measured(result.text, size)
        let previousHeight = measured(prior, result.previousFontSize)
        let gap = result.text.isEmpty ? 0.0 : 4.0
        if !prior.isEmpty && prior != result.text && previousHeight + gap + result.measuredHeight <= available {
            result.previous = prior; result.measuredHeight += previousHeight + gap
        }
        return result
    }
}

struct CaptionPresentation {
    var caption: VisibleCaption
    var english: EnglishCaptionLayout?
}
