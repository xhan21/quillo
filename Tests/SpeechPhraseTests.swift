import Foundation

@main enum SpeechPhraseTests {
    static func main() {
        for phrases in [["最初の説明です", "次の道具を比較します", "最後に結果を確認します"],
                        ["Observe the tools", "Build a prototype", "Compare the results"]] {
            let id = UUID()
            var splitter = SpeechPhraseSegmenter(), ids: [UUID] = []
            var text = "", words: [SpeechWord] = []
            for (i, phrase) in phrases.enumerated() {
                if !text.isEmpty { text += " " }
                words.append(SpeechWord(range: NSRange(location: (text as NSString).length, length: (phrase as NSString).length), timestamp: Double(i) * 3, duration: 1.8))
                text += phrase
                let updates = splitter.receive(SpeechSnapshot(segmentID: id, text: text, words: words), final: false, now: Double(i) * 3)
                precondition(updates.last?.snapshot.text == phrase, "One cumulative recognition task must advance to the new phrase without punctuation")
                if i > 0 { precondition(updates.first?.final == true && updates.first?.snapshot.segmentID == ids.last) }
                ids.append(updates.last!.snapshot.segmentID)
                let repeatResult = splitter.receive(SpeechSnapshot(segmentID: id, text: text, words: words), final: false, now: Double(i) * 3 + 0.1)
                precondition(repeatResult.count == 1 && repeatResult[0].snapshot.segmentID == ids.last, "Repeated callbacks must not replay old phrases")
            }
            precondition(Set(ids).count == 3)
            let final = splitter.receive(SpeechSnapshot(segmentID: id, text: text, words: words), final: true, now: 9)
            precondition(final.count == 1 && final[0].final && final[0].snapshot.segmentID == ids.last)
        }
        // A partial result can revise the length of an earlier word after a split.
        var revised = SpeechPhraseSegmenter()
        let id = UUID()
        _ = revised.receive(SpeechSnapshot(segmentID: id, text: "猫 犬", words: [SpeechWord(range: NSRange(location: 0, length: 1), timestamp: 0, duration: 1), SpeechWord(range: NSRange(location: 2, length: 1), timestamp: 3, duration: 1)]), final: false, now: 0)
        let correction = revised.receive(SpeechSnapshot(segmentID: id, text: "ねこ 犬と遊ぶ", words: [SpeechWord(range: NSRange(location: 0, length: 2), timestamp: 0, duration: 1), SpeechWord(range: NSRange(location: 3, length: 4), timestamp: 3.05, duration: 1.3)]), final: false, now: 0.1)
        precondition(correction.count == 1 && correction[0].snapshot.text == "犬と遊ぶ", "Use audio timing to survive changed text ranges")
        // If Apple omits timing, a settled prefix still advances after a pause.
        var fallback = SpeechPhraseSegmenter()
        _ = fallback.receive(SpeechSnapshot(segmentID: id, text: "最初の説明"), final: false, now: 0)
        let next = fallback.receive(SpeechSnapshot(segmentID: id, text: "最初の説明次の説明"), final: false, now: 1)
        precondition(next.count == 2 && next[0].snapshot.text == "最初の説明" && next[1].snapshot.text == "次の説明")
        var continuous = SpeechPhraseSegmenter()
        var full = ""
        var finals: [String] = [], last = ""
        for i in 0..<48 {
            full += "語\(i) "
            let result = continuous.receive(SpeechSnapshot(segmentID: id, text: full), final: false, now: Double(i) * 0.25)
            finals += result.filter(\.final).map { $0.snapshot.text }
            last = result.last!.snapshot.text
        }
        precondition(!finals.isEmpty && (finals + [last]).joined(separator: " ") == captionText(full), "No content lost or repeated across no-timing phrase boundaries")
        var placeholders = SpeechPhraseSegmenter()
        _ = placeholders.receive(SpeechSnapshot(segmentID: id, text: "最初の説明", words: [SpeechWord(range: NSRange(location: 0, length: 5), timestamp: 0, duration: 0.011)]), final: false, now: 0)
        let second = placeholders.receive(SpeechSnapshot(segmentID: id, text: "最初の説明。次の説明", words: [SpeechWord(range: NSRange(location: 0, length: 6), timestamp: 0, duration: 0.011), SpeechWord(range: NSRange(location: 6, length: 4), timestamp: 0.011, duration: 0.011)]), final: false, now: 2)
        precondition(second.count == 2 && second[0].snapshot.text == "最初の説明。" && second[1].snapshot.text == "次の説明", "Actual Apple placeholder timings must not disable pause detection")
        var rapid = SpeechPhraseSegmenter()
        _ = rapid.receive(SpeechSnapshot(segmentID: id, text: "今日は"), final: false, now: 0)
        let partial = rapid.receive(SpeechSnapshot(segmentID: id, text: "今日は説明します"), final: false, now: 0.2)
        precondition(partial.count == 1 && partial[0].snapshot.segmentID == id, "Normal partial results remain live revisions")
        var english = SpeechPhraseSegmenter()
        _ = english.receive(SpeechSnapshot(segmentID: id, text: "A com"), final: false, now: 0)
        precondition(english.receive(SpeechSnapshot(segmentID: id, text: "A computer"), final: false, now: 2).count == 1, "Do not split a partial English word")
        for (partial, complete) in [("大", "大丈夫"), ("大丈", "大丈夫です"), ("だい", "だいじょうぶ"),
                                    ("試作", "試作品"), ("大丈夫", "大丈夫です"), ("大丈夫です", "大丈夫ですか"),
                                    ("大丈夫じゃ", "大丈夫じゃないです"), ("👩", "👩‍🏫大丈夫です")] {
            var startup = SpeechPhraseSegmenter()
            _ = startup.receive(.init(segmentID: id, text: partial), final: false, now: 0)
            let completeResult = startup.receive(.init(segmentID: id, text: complete), final: false, now: 1.5)
            precondition(completeResult.count == 1 && completeResult[0].snapshot.text == complete && completeResult[0].snapshot.segmentID == id,
                         "A delayed opening word/ending must stay complete: \(partial) -> \(complete)")
            let finalResult = startup.receive(.init(segmentID: id, text: complete), final: true, now: 2)
            precondition(finalResult.count == 1 && finalResult[0].snapshot.text == complete && finalResult[0].final)
        }
        var partialNextWord = SpeechPhraseSegmenter()
        _ = partialNextWord.receive(.init(segmentID: id, text: "説明が終わりました大"), final: false, now: 0)
        let wholeNextWord = partialNextWord.receive(.init(segmentID: id, text: "説明が終わりました大丈夫です"), final: false, now: 1.2)
        precondition(wholeNextWord.count == 2 && wholeNextWord[0].snapshot.text == "説明が終わりました" && wholeNextWord[1].snapshot.text == "大丈夫です",
                     "Keep the next word's leading character with that word, not in prior history")
        var timedWord = SpeechPhraseSegmenter()
        let timedWhole = timedWord.receive(.init(segmentID: id, text: "大丈夫です", words: [
            SpeechWord(range: NSRange(location: 0, length: 1), timestamp: 0, duration: 0.4),
            SpeechWord(range: NSRange(location: 1, length: 4), timestamp: 1.4, duration: 1)]), final: false, now: 2)
        precondition(timedWhole.count == 1 && timedWhole[0].snapshot.text == "大丈夫です", "Even timed ASR segments cannot divide a recognized word")
        // Continuous timed speech advances at a word boundary even without pauses.
        var bounded = SpeechPhraseSegmenter()
        let value = "one two three"
        let all = bounded.receive(SpeechSnapshot(segmentID: id, text: value, words: [SpeechWord(range: NSRange(location: 0, length: 3), timestamp: 0, duration: 4), SpeechWord(range: NSRange(location: 4, length: 3), timestamp: 4, duration: 4), SpeechWord(range: NSRange(location: 8, length: 5), timestamp: 8, duration: 1)]), final: false, now: 0)
        precondition(all.count == 2 && all[0].snapshot.text == "one two" && all[1].snapshot.text == "three")
        var reset = SpeechPhraseSegmenter()
        let sameTask = UUID()
        let settled = SpeechSnapshot(segmentID: sameTask, text: "ちゃんと聞こえます", words: [SpeechWord(range: NSRange(location: 0, length: 4), timestamp: 0, duration: 0.4), SpeechWord(range: NSRange(location: 4, length: 5), timestamp: 0.4, duration: 0.8)])
        _ = reset.receive(settled, final: false, now: 0)
        _ = reset.receive(settled, final: false, now: 1.7)
        let resetResult = reset.receive(.init(segmentID: sameTask, text: "最後", words: [.init(range: NSRange(location: 0, length: 2), timestamp: 0, duration: 0.011)]), final: false, now: 1.9)
        precondition(resetResult.count == 2 && resetResult[0].final && resetResult[0].snapshot.text == settled.text && resetResult[1].snapshot.text == "最後" && resetResult[1].snapshot.segmentID != sameTask,
                     "A recognizer's in-task transcript reset must retain the settled sentence")
        var revision = SpeechPhraseSegmenter()
        _ = revision.receive(settled, final: false, now: 0)
        let quickRevision = revision.receive(.init(segmentID: sameTask, text: "ちゃんと聞こえた", words: [.init(range: NSRange(location: 0, length: 8), timestamp: 0, duration: 0.011)]), final: false, now: 0.1)
        precondition(quickRevision.count == 1 && quickRevision[0].snapshot.segmentID == sameTask, "Quick revisions must not create false history")
        print("PASS: one continuous recognition task, no punctuation, audio pauses, timing corrections, missing timing, continuous speech bound, finalization and partial word safety")
    }
}
