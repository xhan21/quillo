import Foundation

struct SpeechSnapshot {
    let segmentID: UUID
    let text: String
    var words: [SpeechWord] = []
}

struct SpeechWord {
    let range: NSRange
    let timestamp: TimeInterval
    let duration: TimeInterval
}

struct SpeechPhraseUpdate {
    let snapshot: SpeechSnapshot
    let final: Bool
}

// One Apple recognition task can contain many phrases, with no sentence marks.
// Split the live cumulative transcript without stopping the audio engine.
struct SpeechPhraseSegmenter {
    static let pause = 0.8
    static let maximumDuration = 8.0
    private var recognitionID: UUID?
    private var cueID = UUID()
    private var anchorTime: Double?
    private var offset = 0
    private var lastFullText = ""
    private var lastChange = 0.0
    private var beganAt = 0.0

    mutating func receive(_ snapshot: SpeechSnapshot, final: Bool, now: Double) -> [SpeechPhraseUpdate] {
        if recognitionID != snapshot.segmentID {
            self = Self(); recognitionID = snapshot.segmentID; cueID = snapshot.segmentID
            beganAt = now; lastChange = now
        }
        let raw = snapshot.text as NSString
        guard raw.length > 0 else { return [] }
        let words = snapshot.words.filter {
            $0.range.location >= 0 && $0.range.length > 0 && $0.range.location <= raw.length - $0.range.length
                && $0.timestamp.isFinite && $0.duration.isFinite && $0.duration >= 0
        }
        // Apple can return placeholder 0.011-second segments in partial results.
        // Those are token counters, not usable audio timing; use arrival time then.
        let timed = words.count > 1 && zip(words, words.dropFirst()).allSatisfy { $0.timestamp <= $1.timestamp }
            && words.contains { $0.duration >= 0.04 }
            && words.last!.timestamp - words.first!.timestamp >= 0.2
        var start = min(offset, raw.length)
        if timed, let anchorTime {
            guard let word = words.first(where: { $0.timestamp >= anchorTime }) else { return [] }
            start = word.range.location
        }
        var output: [SpeechPhraseUpdate] = []
        func append(_ value: String, id: UUID, final: Bool) {
            let clean = captionText(value)
            if !clean.isEmpty { output.append(SpeechPhraseUpdate(snapshot: SpeechSnapshot(segmentID: id, text: clean), final: final)) }
        }
        if timed, let first = words.firstIndex(where: { $0.range.location >= start }) {
            var phraseFirst = first
            for i in words.indices where i > first {
                let previous = words[i - 1], word = words[i]
                let gap = word.timestamp - (previous.timestamp + previous.duration)
                let duration = word.timestamp - words[phraseFirst].timestamp
                guard gap >= Self.pause || duration >= Self.maximumDuration else { continue }
                let boundary = word.range.location
                guard boundary > start else { continue }
                append(raw.substring(with: NSRange(location: start, length: boundary - start)), id: cueID, final: true)
                cueID = UUID(); start = boundary; phraseFirst = i; beganAt = now
                // Use the gap between word starts, so small timing/range revisions
                // before this phrase do not replay the preceding text.
                anchorTime = (previous.timestamp + word.timestamp) / 2
            }
        } else if snapshot.text != lastFullText, !lastFullText.isEmpty,
                  snapshot.text.hasPrefix(lastFullText),
                  now - lastChange >= Self.pause || now - beganAt >= Self.maximumDuration {
            // Some partial results omit timing. A settled prefix is a safe fallback.
            // Do not split an unfinished English word in the middle.
            var boundary = (lastFullText as NSString).length
            // A new partial may add the preceding sentence's punctuation now.
            while boundary < raw.length, " .!?。！？,、，;；\n\t".contains(raw.substring(with: NSRange(location: boundary, length: 1))) { boundary += 1 }
            let suffix = raw.substring(from: boundary)
            let isWordContinuation = boundary == (lastFullText as NSString).length && lastFullText.last?.isASCII == true && lastFullText.last?.isLetter == true
                && suffix.first?.isASCII == true && suffix.first?.isLetter == true
            if boundary > start && boundary < raw.length && !isWordContinuation {
                append(raw.substring(with: NSRange(location: start, length: boundary - start)), id: cueID, final: true)
                cueID = UUID(); start = boundary; beganAt = now
            }
        }
        offset = start
        append(raw.substring(from: start), id: cueID, final: final)
        if lastFullText != snapshot.text { lastChange = now }
        lastFullText = snapshot.text
        return output
    }
}

// A new hypothesis replaces the pending hypothesis for the same utterance.
// Completed utterances retain one final job for their full transcript. The live
// utterance always has priority over these background transcript translations.
struct TranslationMailbox {
    private var pending: [UUID: TranslationJob] = [:]
    private var order: [UUID] = []
    var preferredID: UUID?
    var count: Int { pending.count }
    var isEmpty: Bool { pending.isEmpty }

    mutating func submit(_ job: TranslationJob) {
        if pending[job.cueID] == nil { order.append(job.cueID) }
        if let previous = pending[job.cueID], previous.revision > job.revision { return }
        pending[job.cueID] = job
    }
    mutating func takeNext() -> TranslationJob? {
        guard let id = preferredID.flatMap({ pending[$0] != nil ? $0 : nil }) ?? order.first else { return nil }
        order.removeAll { $0 == id }
        return pending.removeValue(forKey: id)
    }
    mutating func removeAll() { pending.removeAll(); order.removeAll(); preferredID = nil }
}
