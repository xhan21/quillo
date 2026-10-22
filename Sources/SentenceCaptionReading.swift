import AppKit
import NaturalLanguage

// Presentation only: never changes translation jobs or the full transcript.
// There is one replaceable pending hypothesis, not a queue of old captions.
struct SentenceCaptionReading {
    static let updateInterval = 0.65
    private struct Cue {
        let id: UUID
        var text = ""
        var current = ""
        var completed: [String] = []
        var position = 0
        var sentences: [String] { completed + (current.isEmpty ? [] : [current]) }

        mutating func update(_ value: String, sourcePosition: Int?, language: CaptionLanguage) {
            let parts = SentenceCaptionLayout.sentences(value, language: language)
            guard let last = parts.last else { return }
            let source = max(0, sourcePosition ?? 0), translated = parts.count - 1
            if current.isEmpty {
                completed = Array(parts.dropLast().suffix(2))
            } else {
                // Recognition and translation may revise punctuation independently.
                // Retain the sentence actually displayed when either moves forward.
                let advance = max(source, translated) - position
                if advance > 0 {
                    completed = Array((completed + [current] + parts.dropLast().suffix(max(0, advance - 1))).suffix(2))
                }
            }
            position = max(position, source, translated)
            current = last; text = value
        }
    }
    private struct Pending { let text: String; let sourcePosition: Int? }
    private var active: Cue?
    // Keep empty slots too: a delayed translation belongs to its original cue.
    private var retired: [Cue] = []
    var text: String { active?.text ?? "" }
    var currentText: String { active?.current ?? "" }
    var history: [String] { Array((retired.flatMap(\.sentences) + (active?.completed ?? [])).suffix(2)) }
    var previous: String { history.last ?? "" }
    private var pending: Pending?
    private var lastDisplay = -Double.infinity
    private var language: CaptionLanguage = .english
    var nextWakeup: Double? { pending == nil ? nil : lastDisplay + Self.updateInterval }

    mutating func begin(_ id: UUID, language: CaptionLanguage = .english, now: Double) {
        guard active?.id != id || self.language != language else { return }
        if self.language != language { retired = [] }
        else if let active { retired = Array((retired + [active]).suffix(2)) }
        self.language = language
        active = Cue(id: id); pending = nil; lastDisplay = -.infinity
    }
    mutating func receive(_ value: String, now: Double, final: Bool = false, cueID: UUID? = nil, sourcePosition: Int? = nil) {
        guard !value.isEmpty else { return }
        if let cueID, cueID != active?.id {
            if let index = retired.firstIndex(where: { $0.id == cueID }) {
                retired[index].update(value, sourcePosition: sourcePosition, language: language)
            }
            return
        }
        if value == text && sourcePosition == nil { pending = nil; return }
        if text.isEmpty || final || now - lastDisplay >= Self.updateInterval {
            active?.update(value, sourcePosition: sourcePosition, language: language)
            lastDisplay = now; pending = nil
        } else { pending = Pending(text: value, sourcePosition: sourcePosition) }
    }
    mutating func flush(now: Double) {
        if let pending {
            active?.update(pending.text, sourcePosition: pending.sourcePosition, language: language)
            lastDisplay = now; self.pending = nil
        }
    }
    // Clear obsolete translation content while retaining its history slot.
    mutating func invalidate(cueID: UUID) {
        if active?.id == cueID { active = Cue(id: cueID); pending = nil; lastDisplay = -.infinity }
        else if let index = retired.firstIndex(where: { $0.id == cueID }) { retired[index] = Cue(id: cueID) }
    }
    // A proofreading result replaces this cue in place. Re-punctuation is not
    // a new utterance and must not archive the uncorrected version as history.
    mutating func replace(_ value: String, cueID: UUID, now: Double) {
        let parts = SentenceCaptionLayout.sentences(value, language: language)
        guard let last = parts.last else { return }
        if active?.id == cueID {
            guard active?.text != value else { return }
            active?.text = value; active?.current = last; active?.completed = Array(parts.dropLast().suffix(2))
            pending = nil; lastDisplay = now
        } else if let index = retired.firstIndex(where: { $0.id == cueID }) {
            guard retired[index].text != value else { return }
            retired[index].text = value; retired[index].current = last; retired[index].completed = Array(parts.dropLast().suffix(2))
        }
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
    static func context(text: String, history: [String], language: CaptionLanguage, historyLimit: Int = 2) -> (current: String, prior: [String]) {
        let parts = sentences(text, language: language)
        return (parts.last ?? "", Array((history + parts.dropLast()).suffix(max(0, min(2, historyLimit)))))
    }
    static func historySize(_ size: Double) -> Double { min(size, max(14, size * 0.8)) }
    static func minimumHeight(fontSize: Double, historyLimit: Int = 2) -> Double {
        CaptionTypesetting.lineHeight(min(fontSize, 18)) + Double(max(0, min(2, historyLimit))) * (CaptionTypesetting.lineHeight(historySize(min(fontSize, 18))) + 4)
    }
    static func preferredHeight(text: String, history: [String], fontSize: Double, width: Double, language: CaptionLanguage, historyLimit: Int = 2) -> Double {
        let (current, prior) = context(text: text, history: history, language: language, historyLimit: historyLimit)
        return max(minimumHeight(fontSize: fontSize, historyLimit: historyLimit),
            Double(CaptionTypesetting.lineCount(current, size: fontSize, width: width)) * CaptionTypesetting.lineHeight(fontSize)
            + prior.reduce(0.0) { $0 + Double(CaptionTypesetting.lineCount($1, size: historySize(fontSize), width: width)) * CaptionTypesetting.lineHeight(historySize(fontSize)) + 4 })
    }
    static func layout(text: String, history: [String], fontSize: Double, width: Double, height: Double, language: CaptionLanguage = .english, historyLimit: Int = 2) -> Self {
        let (current, prior) = context(text: text, history: history, language: language, historyLimit: historyLimit)
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
