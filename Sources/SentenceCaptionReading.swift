import AppKit
import NaturalLanguage

// Presentation only: never changes translation jobs or the full transcript.
// There is one replaceable pending hypothesis, not a queue of old captions.
struct SentenceCaptionReading {
    static let updateInterval = 0.65
    private(set) var text = ""
    private(set) var history: [String] = [] // Oldest first; at most two prior sentences.
    var previous: String { history.last ?? "" }
    private var latest = ""
    private var pending: String?
    private var lastDisplay = -Double.infinity
    private var cue: UUID?
    private var language: CaptionLanguage = .english
    var nextWakeup: Double? {
        pending == nil ? nil : lastDisplay + Self.updateInterval
    }
    mutating func begin(_ id: UUID, language: CaptionLanguage = .english, now: Double) {
        guard cue != id || self.language != language else { return }
        // Promote only when the utterance changes, never on a partial correction.
        // A recognizer's final phrase may have no punctuation; retain it as heard.
        history = self.language == language
            ? Array((history + SentenceCaptionLayout.sentences(latest, language: language)).suffix(2)) : []
        self.language = language
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
        if now - lastDisplay >= Self.updateInterval { flush(now: now) }
    }
}

struct SentenceCaptionLayout {
    var text: String
    var history: [String] = []
    var previous: String { history.last ?? "" }
    var fontSize: Double
    var previousFontSize: Double
    var continued = false
    var height: Double {
        // Measured by layout(), retained as a testable bound on the rendered block.
        measuredHeight
    }
    private var measuredHeight = 0.0

    static func supports(_ language: CaptionLanguage) -> Bool { true }
    private static func tokenizer(_ unit: NLTokenUnit, text: String, language: CaptionLanguage) -> NLTokenizer {
        let tokenizer = NLTokenizer(unit: unit)
        tokenizer.setLanguage(language.isChinese ? (language == .chinese ? .simplifiedChinese : .traditionalChinese) : language == .japanese ? .japanese : .english)
        tokenizer.string = text
        return tokenizer
    }
    static func sentences(_ text: String, language: CaptionLanguage = .english) -> [String] {
        guard !text.isEmpty else { return [] }
        let tokenizer = tokenizer(.sentence, text: text, language: language)
        return tokenizer.tokens(for: text.startIndex..<text.endIndex)
            .map { captionText(String(text[$0])) }.filter { !$0.isEmpty }
    }
    static func isComplete(_ text: String) -> Bool {
        let end = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'”’)]}」』）】》〉")))
        return end.last.map { ".!?。！？".contains($0) } == true
    }
    static func layout(text: String, previous: String, fontSize: Double, width: Double, height: Double, language: CaptionLanguage = .english) -> Self {
        layout(text: text, history: previous.isEmpty ? [] : [previous], fontSize: fontSize, width: width, height: height, language: language)
    }
    static func context(text: String, history: [String], language: CaptionLanguage) -> (current: String, prior: [String]) {
        let parts = sentences(text, language: language)
        return (parts.last ?? "", Array((history + parts.dropLast()).suffix(2)))
    }
    static func historySize(_ size: Double) -> Double { min(size, max(14, size * 0.8)) }
    static func minimumHeight(fontSize: Double) -> Double {
        CaptionTypesetting.lineHeight(min(fontSize, 18)) + 2 * CaptionTypesetting.lineHeight(historySize(min(fontSize, 18))) + 8
    }
    static func preferredHeight(text: String, history: [String], fontSize: Double, width: Double, language: CaptionLanguage) -> Double {
        let (current, prior) = context(text: text, history: history, language: language)
        return max(minimumHeight(fontSize: fontSize),
            Double(CaptionTypesetting.lineCount(current, size: fontSize, width: width)) * CaptionTypesetting.lineHeight(fontSize)
            + prior.reduce(0.0) { $0 + Double(CaptionTypesetting.lineCount($1, size: historySize(fontSize), width: width)) * CaptionTypesetting.lineHeight(historySize(fontSize)) + 4 })
    }
    static func layout(text: String, history: [String], fontSize: Double, width: Double, height: Double, language: CaptionLanguage = .english) -> Self {
        let (current, prior) = context(text: text, history: history, language: language)
        let available = max(1, height), width = max(1, width)
        func measured(_ value: String, _ size: Double) -> Double {
            Double(CaptionTypesetting.lineCount(value, size: size, width: width)) * CaptionTypesetting.lineHeight(size)
        }
        // Fit all three sentences before shortening any display block. No timer
        // expires the history; only the arrival of newer sentences displaces it.
        let minimum = min(fontSize, 18)
        var size = fontSize
        func total(_ size: Double) -> Double {
            measured(current, size) + prior.reduce(0.0) { $0 + measured($1, historySize(size)) }
                + Double(max(0, prior.count + (current.isEmpty ? 0 : 1) - 1)) * 4
        }
        while size > minimum && total(size) > available { size = max(minimum, size - 1) }
        var result = Self(text: current, fontSize: size, previousFontSize: historySize(size))
        let priorLine = CaptionTypesetting.lineHeight(result.previousFontSize)
        // Reserve one line for each history entry. The app's minimum height
        // guarantees these rows; tiny standalone layouts still prioritize now.
        let currentMinimum = current.isEmpty ? 0 : CaptionTypesetting.lineHeight(size)
        let kept = Array(prior.suffix(max(0, min(prior.count, Int((available - currentMinimum) / (priorLine + 4))))))
        let currentBudget = available - Double(kept.count) * (priorLine + 4)
        if measured(current, size) > currentBudget {
            // Exceptionally long sentences use a clause/word boundary, rather
            // than dropping an arbitrary first line. Never add or rewrite words.
            let lines = max(1, Int(currentBudget / CaptionTypesetting.lineHeight(size)))
            let tail = CaptionViewport.tail(current, size: size, width: width, lines: lines, weight: .regular)
            let start = current.index(current.endIndex, offsetBy: -tail.count)
            var boundaries = current.indices.filter { index in
                guard index >= start, index > current.startIndex else { return false }
                let before = current[current.index(before: index)]
                return before.isWhitespace && !current[index].isWhitespace
            }
            if language.isChinese || language == .japanese {
                // Chinese has no spaces between words. Prefer punctuation, then
                // the system word tokenizer; never split a composed character.
                boundaries = tokenizer(.word, text: current, language: language)
                    .tokens(for: current.startIndex..<current.endIndex).map(\.lowerBound)
                    .filter { $0 >= start && $0 > current.startIndex }
            }
            let clauses = (language.isChinese || language == .japanese ? Array(current.indices) : boundaries).filter { index in
                guard index >= start, index > current.startIndex, !current[index].isWhitespace else { return false }
                let prefix = current[..<index].trimmingCharacters(in: .whitespacesAndNewlines)
                return prefix.last.map { ",;:—，；：、".contains($0) } == true
            }
            let boundary = clauses.first ?? boundaries.first ?? start
            result.text = String(current[boundary...]); result.continued = boundary > current.startIndex
        }
        result.measuredHeight = measured(result.text, size)
        var remaining = available - result.measuredHeight
        // Newer context gets first use of spare lines, but both entries keep a row.
        for (index, value) in kept.reversed().enumerated() {
            let gap = result.text.isEmpty && result.history.isEmpty ? 0.0 : 4.0
            let reserved = Double(kept.count - index - 1) * (priorLine + 4)
            let lines = max(1, Int((remaining - gap - reserved) / priorLine))
            let visible = CaptionViewport.tail(value, size: result.previousFontSize, width: width, lines: lines, weight: .regular)
            result.history.insert(visible, at: 0)
            let used = measured(visible, result.previousFontSize) + gap
            result.measuredHeight += used; remaining -= used
            result.continued = result.continued || visible != value
        }
        return result
    }
}

struct CaptionPresentation {
    var caption: VisibleCaption
    var reading: SentenceCaptionLayout?
    var sourceReading: SentenceCaptionLayout? = nil
}
