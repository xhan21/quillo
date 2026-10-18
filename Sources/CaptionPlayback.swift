import Foundation

struct SpeechSnapshot {
    let segmentID: UUID
    let text: String
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
