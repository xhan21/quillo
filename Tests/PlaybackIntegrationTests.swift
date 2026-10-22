import AppKit

@MainActor final class ControlledTranslator {
    struct Call { let text: String; let continuation: CheckedContinuation<String, Error> }
    var calls: [Call] = []
    var active = 0
    var maximumActive = 0
    func translate(_ text: String) async throws -> String {
        active += 1; maximumActive = max(maximumActive, active)
        defer { active -= 1 }
        return try await withCheckedThrowingContinuation { calls.append(Call(text: text, continuation: $0)) }
    }
    func complete(_ value: String) { calls.removeFirst().continuation.resume(returning: value) }
    func fail() { calls.removeFirst().continuation.resume(throwing: NSError(domain: "test", code: 1)) }
}

@main enum PlaybackIntegrationTests {
    @MainActor static func eventually(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        preconditionFailure("Timed out")
    }
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let model = AppModel(glossary: GlossaryStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
        model.clearCaption(); model.isListening = true
        let originalMode = model.displayMode
        defer { model.displayMode = originalMode }
        let id = UUID()
        func speech(_ text: String, final: Bool = false, segment: UUID = id) {
            model.speech.onText?(SpeechSnapshot(segmentID: segment, text: text), final)
        }
        let start = ContinuousClock.now
        speech("今日は")
        precondition(model.sourceText == "今日は" && model.logs.count == 1, "The first partial result must show before any async work or translation preparation")
        let updateTime = start.duration(to: .now)
        model.displayMode = .translationOnly
        precondition(model.visibleCaption.source.isEmpty && !model.visibleCaption.placeholder.isEmpty)
        model.displayMode = .bilingual
        precondition(model.visibleCaption.source == "今日は")
        let translator = ControlledTranslator()
        let worker = Task { await model.runTranslationWorker(prepare: {}, translate: { try await translator.translate($0) }) }
        try await eventually { translator.calls.count == 1 }
        for n in 1...100 { speech("今日は身近な道具を観察します。\(n)") }
        let full = "今日は身近な道具を観察します。100"
        precondition(model.sourceText == full && model.logs.count == 1 && model.logs[0].source == full)
        precondition(model.pendingTranslationCount == 1 && translator.calls.count == 1)
        translator.complete("Today")
        try await eventually { model.translatedText == "Today" }
        precondition(model.translationUpdating && model.logs[0].translationIncomplete, "Partial translations must appear even while speech continues")
        try await eventually { translator.calls.count == 1 }
        precondition(translator.calls[0].text == full, "Skip obsolete intermediate jobs")
        translator.complete("Today, observe everyday tools. 100")
        try await eventually { !model.translationUpdating }
        precondition(!model.logs[0].translationIncomplete)
        speech(full, final: true)
        precondition(model.logs.count == 1 && model.pendingTranslationCount == 0, "Same final result must not duplicate log or translation")

        let second = UUID(), third = UUID()
        speech("二つ目", segment: second)
        precondition(model.sourceText == "二つ目" && model.translatedText.isEmpty)
        try await eventually { translator.calls.count == 1 }
        speech("三つ目", segment: third)
        translator.complete("Second")
        try await eventually { model.logs[1].translation == "Second" }
        precondition(model.sentenceReading.previous == "Second", "Late first translation fills the preceding history slot")
        precondition(model.sourceText == "三つ目" && model.translatedText.isEmpty, "An old utterance can update its log, never the new caption")
        try await eventually { translator.calls.count == 1 }
        translator.fail()
        try await eventually { model.liveTranslationFailed }
        speech("三つ目の続き", final: true, segment: third)
        precondition(model.sourceText == "三つ目の続き" && !model.liveTranslationFailed)
        try await eventually { translator.calls.count == 1 }
        translator.complete("Third, continued")
        try await eventually { model.translatedText == "Third, continued" }

        let fourth = UUID(), fifth = UUID()
        speech("前の文", segment: fourth)
        try await eventually { translator.calls.count == 1 }
        speech("前の文の確定結果。", final: true, segment: fourth)
        speech("今の文", segment: fifth)
        translator.complete("Previous")
        try await eventually { translator.calls.count == 1 }
        precondition(translator.calls[0].text == "今の文")
        translator.complete("Current")
        try await eventually { translator.calls.count == 1 }
        precondition(translator.calls[0].text == "前の文の確定結果。")
        translator.complete("Previous final result.")
        try await eventually { model.logs[3].translation == "Previous final result." }
        precondition(model.translatedText == "Current" && !model.logs[3].translationIncomplete)
        precondition(model.sentenceReading.history == ["Third, continued", "Previous final result."], "Late final corrects history without replacing the current caption")

        speech("消去前の発話", segment: UUID())
        try await eventually { translator.calls.count == 1 }
        model.clearCaption()
        translator.complete("Must never reappear")
        try await eventually { translator.active == 0 }
        precondition(model.sourceText.isEmpty && model.translatedText.isEmpty)
        model.speech.onText?(SpeechSnapshot(segmentID: UUID(), text: "Stopped callback"), false)
        precondition(model.sourceText.isEmpty, "Stopped capture callbacks must be ignored")
        worker.cancel(); await worker.value
        precondition(translator.maximumActive == 1)
        model.setCaptionMode(nil); model.clearCaption()
        let long = String(repeating: "全文をログに残します。👩🏽‍🏫", count: 100) + "最後です。"
        model.typedText = long; model.sendTypedCaption()
        precondition(model.sourceText == long && model.logs.last?.source == long)
        precondition(long.hasSuffix(model.visibleCaption.source) && model.visibleCaption.source.hasSuffix("最後です。"))
        model.shutdown()
        try await openingWord()
        try await continuousMicrophoneHistory()
        try await modeSwitching()
        for language in [CaptionLanguage.english, .chinese, .traditionalChinese] { try await sentenceReadingMode(language) }
        print("PASS: synchronous original update (\(updateTime)), partial translation progress, coalescing, no duplicated finals, no stale overwrite, live priority + final logs, errors recover, clear cancels, full logs, one translation in flight")
    }

    @MainActor static func openingWord() async throws {
        let model = AppModel(glossary: GlossaryStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
        let savedMode = model.displayMode
        defer { model.displayMode = savedMode; model.shutdown() }
        model.clearCaption(); model.setCaptionMode(.bilingual); model.isListening = true; model.isStartingMic = true
        let translator = ControlledTranslator(), id = UUID(), session = model.translationSessionID
        let worker = Task { await model.runTranslationWorker(prepare: {}, translate: { try await translator.translate($0) }) }
        model.speech.onText?(.init(segmentID: id, text: "大", words: [.init(range: NSRange(location: 0, length: 1), timestamp: 0, duration: 0.011)]), false)
        try await eventually { translator.calls.count == 1 }
        // Reproduce the initial delayed callback that previously split 大|丈夫.
        try await Task.sleep(for: .milliseconds(950))
        model.speech.onText?(.init(segmentID: id, text: "大丈夫です", words: [.init(range: NSRange(location: 0, length: 5), timestamp: 0, duration: 0.011)]), true)
        precondition(model.sourceText == "大丈夫です" && model.sourceReading.history.isEmpty && model.logs.map(\.source) == ["大丈夫です"])
        precondition(model.isListening && model.translationSessionID == session)
        translator.complete("Large")
        try await eventually { translator.calls.count == 1 }
        precondition(translator.calls[0].text == "大丈夫です", "The translator must receive the whole word, not 丈夫")
        translator.complete("It's okay.")
        try await eventually { model.translatedText == "It's okay." }
        precondition(model.sentenceReading.history.isEmpty && model.logs.count == 1)
        model.clearCaption(); worker.cancel(); await worker.value
        print("PASS: delayed startup 大 -> 大丈夫です retains the full word in original, translation and history")
    }

    @MainActor static func continuousMicrophoneHistory() async throws {
        let model = AppModel(glossary: GlossaryStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
        let savedMode = model.displayMode, savedHistory = model.historySettings
        defer { model.displayMode = savedMode; model.historySettings = savedHistory; model.shutdown() }
        model.clearCaption(); model.setCaptionMode(.bilingual); model.historySettings = CaptionHistorySettings(); model.isListening = true
        let translator = ControlledTranslator(), taskID = UUID()
        let worker = Task { await model.runTranslationWorker(prepare: {}, translate: { try await translator.translate($0) }) }
        let phrases = ["身近な道具を観察します", "次に試作品を作ります", "最後に比較します", "気づきを発表します"]
        let translations = ["Observe familiar tools", "Build a prototype", "Compare the results", "Present your findings"]
        var full = "", words: [SpeechWord] = []
        let session = model.translationSessionID
        for i in phrases.indices {
            if !full.isEmpty { full += " " }
            words.append(SpeechWord(range: NSRange(location: (full as NSString).length, length: (phrases[i] as NSString).length), timestamp: Double(i) * 4, duration: 2))
            full += phrases[i]
            model.speech.onText?(SpeechSnapshot(segmentID: taskID, text: full, words: words), false)
            precondition(model.sourceText == phrases[i], "Mic callbacks from the same recognition ID advance immediately")
            try await eventually { translator.calls.count == 1 }
            precondition(translator.calls[0].text == phrases[i], "Translate the new phrase, not a growing lecture transcript")
            translator.complete(translations[i])
            try await eventually { model.visibleCaption.translation == translations[i] }
            precondition(model.sourceReading.history == Array(phrases.prefix(i).suffix(2)))
            precondition(model.sentenceReading.history == Array(translations.prefix(i).suffix(2)))
            precondition(model.translationSessionID == session && model.isListening)
        }
        precondition(model.logs.map(\.source) == phrases && model.logs.map(\.translation) == translations)
        model.historySettings.count = 1
        precondition(model.captionPresentation.reading?.history == [translations[2]])
        model.historySettings.enabled = false
        precondition(model.captionPresentation.reading?.history.isEmpty == true)
        model.historySettings.enabled = true
        precondition(model.captionPresentation.reading?.history == [translations[2]])
        model.clearCaption(); worker.cancel(); await worker.value
        print("PASS: cumulative unpunctuated microphone callbacks advance original and translated history without restarting recognition/session")
    }

    @MainActor static func modeSwitching() async throws {
        let model = AppModel(glossary: GlossaryStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
        let originalMode = model.displayMode
        defer { model.displayMode = originalMode; model.shutdown() }
        model.clearCaption(); model.setCaptionMode(nil)
        model.isListening = true
        let id = UUID()
        func speech(_ text: String) { model.speech.onText?(SpeechSnapshot(segmentID: id, text: text), false) }
        speech("最初")
        precondition(model.pendingTranslationCount == 0 && !model.logs[0].translationIncomplete)
        model.setCaptionMode(.translationOnly)
        precondition(model.isListening && model.sourceText == "最初" && model.logs.count == 1,
                     "The UI mode action must preserve capture, text and transcript identity")
        precondition(model.preparingTranslation && model.translationConfiguration != nil && model.pendingTranslationCount == 1,
                     "Returning from original-only must prepare and queue the existing text without a new speech event")

        let translator = ControlledTranslator()
        let preparation = ControlledTranslator()
        let worker = Task {
            await model.runTranslationWorker(prepare: { _ = try await preparation.translate("prepare") },
                                             translate: { try await translator.translate($0) })
        }
        try await eventually { preparation.calls.count == 1 }
        model.setCaptionMode(nil); speech("準備中の発話")
        model.setCaptionMode(.bilingual); model.setCaptionMode(.translationOnly)
        precondition(model.isListening && model.preparingTranslation && model.sourceText == "準備中の発話")
        preparation.complete("ready")
        try await eventually { translator.calls.count == 1 }
        precondition(translator.calls[0].text == "準備中の発話", "Preparation toggles must keep the newest speech")
        model.setCaptionMode(nil)
        translator.complete("Preparing")
        try await eventually { model.translatedText == "Preparing" }
        precondition(model.visibleCaption.translation.isEmpty && model.visibleCaption.source == "準備中の発話")
        precondition(model.translationReady && !model.preparingTranslation && model.isListening,
                     "Original-only must keep the session and microphone alive")
        speech("原文だけでも聞き続ける")
        precondition(model.pendingTranslationCount == 0 && !model.translationUpdating)
        model.setCaptionMode(.translationOnly)
        try await eventually { translator.calls.count == 1 }
        precondition(translator.calls[0].text == "原文だけでも聞き続ける")
        model.setCaptionMode(.bilingual); model.setCaptionMode(nil); model.setCaptionMode(.translationOnly)
        translator.complete("Keep listening")
        try await eventually { model.visibleCaption.translation == "Keep listening" && !model.translationUpdating }
        precondition(model.visibleCaption.source.isEmpty && model.visibleCaption.translation == "Keep listening")
        model.setCaptionMode(.bilingual)
        precondition(model.visibleCaption.source == "原文だけでも聞き続ける" && model.visibleCaption.translation == "Keep listening")
        precondition(model.isListening && model.translationReady && model.pendingTranslationCount == 0 && model.logs.count == 1,
                     "Repeated display switches must reuse the ready session without duplicate work or replacement samples")

        // An original-only utterance with a new ID also needs translation on
        // return, including after the microphone has stopped.
        model.setCaptionMode(nil); model.stopMic()
        model.typedText = "停止してから切り替える"; model.sendTypedCaption()
        precondition(model.pendingTranslationCount == 0)
        model.setCaptionMode(.bilingual)
        try await eventually { translator.calls.count == 1 }
        precondition(translator.calls[0].text == "停止してから切り替える")
        translator.complete("Switch after stopping")
        try await eventually { model.translatedText == "Switch after stopping" }
        precondition(!model.isListening && model.logs.count == 2 && !model.logs[1].translationIncomplete)

        // An actual language change still invalidates pending results.
        model.typedText = "古い言語の結果"; model.sendTypedCaption()
        try await eventually { translator.calls.count == 1 }
        model.targetLanguage = .japanese; model.languageChanged()
        precondition(!model.translationReady && model.translationConfiguration == nil && !model.requiresTranslation)
        translator.complete("Old language must not return")
        await worker.value
        precondition(model.translatedText != "Old language must not return" && translator.maximumActive == 1)
        print("PASS: UI mode transitions preserve microphone and session, auto-prepare from original-only, resume latest text during preparation/in-flight/idle/stopped capture, bilingual + translation-only visibility, actual language changes invalidate old results")
    }

    @MainActor static func sentenceReadingMode(_ language: CaptionLanguage) async throws {
        // A user who disabled the old optional mode must also get the new standard.
        let defaults = UserDefaults.standard
        let oldPreference = defaults.object(forKey: "readableEnglish.v1")
        defaults.set(false, forKey: "readableEnglish.v1")
        defer {
            if let oldPreference { defaults.set(oldPreference, forKey: "readableEnglish.v1") }
            else { defaults.removeObject(forKey: "readableEnglish.v1") }
        }
        let model = AppModel(glossary: GlossaryStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
        let savedMode = model.displayMode, savedHistory = model.historySettings
        defer { model.displayMode = savedMode; model.historySettings = savedHistory; model.shutdown() }
        model.historySettings = CaptionHistorySettings()
        model.clearCaption(); model.targetLanguage = language; model.languageChanged()
        model.setCaptionMode(.translationOnly); model.isListening = true
        precondition(model.captionPresentation.reading != nil, "Sentence display is always active even when the old saved preference was off")
        let first = language == .english ? "If the condition" : language.normalizeScript("如果条件")
        let complete = language == .english ? "If the condition is true, the result is not false." : language.normalizeScript("如果条件为真，结果就不是假。")
        let next = language == .english ? "Next, compare the examples." : language.normalizeScript("接下来，比较三个例子。")
        let id = UUID(), translator = ControlledTranslator()
        func speech(_ text: String, final: Bool = false, cue: UUID = id) {
            model.speech.onText?(SpeechSnapshot(segmentID: cue, text: text), final)
        }
        let worker = Task { await model.runTranslationWorker(prepare: {}, translate: { try await translator.translate($0) }) }
        speech("条件が")
        try await eventually { translator.calls.count == 1 }
        translator.complete(first)
        try await eventually { model.sentenceReading.text == first }
        let session = model.translationSessionID
        speech("条件が真なら結果は偽ではありません。")
        try await eventually { translator.calls.count == 1 }
        translator.complete(complete)
        try await eventually { model.translatedText == complete }
        precondition(model.logs[0].translation == model.translatedText, "Full logs are updated before any presentation delay")
        try await eventually { model.sentenceReading.text == model.translatedText }
        speech("次の例", cue: UUID())
        precondition(model.translatedText.isEmpty && model.sentenceReading.previous == complete, "The old sentence is a separate context block, never the new translation")
        try await eventually { translator.calls.count == 1 }
        translator.complete(next)
        try await eventually { model.visibleCaption.translation == next }
        model.setCaptionMode(.bilingual)
        precondition(model.captionPresentation.reading != nil && model.visibleCaption.translation == next)
        model.setCaptionMode(nil)
        precondition(model.visibleCaption.translation.isEmpty && model.captionPresentation.reading == nil)
        model.setCaptionMode(.translationOnly)
        precondition(model.isListening && model.translationSessionID == session && model.translationReady && model.captionPresentation.reading != nil, "Display switches keep standard sentence reading without restarting capture or translation")
        speech("三つ目の文です。", cue: UUID())
        try await eventually { translator.calls.count == 1 }
        let third = language == .english ? "A third sentence." : language.normalizeScript("这是第三句。")
        translator.complete(third)
        try await eventually { model.translatedText == third }
        precondition(model.captionPresentation.reading?.history == [complete, next], "Both prior translations are displayed, not just stored")
        model.setCaptionMode(nil)
        precondition(model.captionPresentation.sourceReading?.history == ["条件が真なら結果は偽ではありません。", "次の例"], "Original-only retains two previous spoken phrases")
        model.setCaptionMode(.bilingual)
        precondition(model.captionPresentation.reading?.history == [complete, next] && model.captionPresentation.sourceReading?.history.count == 2)
        precondition(model.isListening && model.translationSessionID == session, "History display switches preserve the live session")
        let logs = model.logs.map { $0.source + $0.translation }
        model.historySettings.count = 1
        precondition(model.captionPresentation.reading?.history == [next] && model.captionPresentation.sourceReading?.history == ["次の例"])
        let oneHistoryHeight = model.minimumPanelHeight
        model.historySettings.enabled = false
        precondition(model.captionPresentation.reading?.history.isEmpty == true && model.captionPresentation.sourceReading?.history.isEmpty == true)
        precondition(model.minimumPanelHeight < oneHistoryHeight && model.visibleCaption.translation == third)
        speech("四つ目の文です。", cue: UUID())
        try await eventually { translator.calls.count == 1 }
        let fourth = language == .english ? "A fourth sentence." : language.normalizeScript("这是第四句。")
        model.historySettings.count = 2; model.historySettings.enabled = true
        precondition(model.captionPresentation.reading?.history == [next, third], "History continues recording while hidden")
        precondition(model.isListening && model.translationSessionID == session && model.translationReady && translator.calls.count == 1)
        translator.complete(fourth)
        try await eventually { model.visibleCaption.translation == fourth }
        precondition(Array(model.logs.prefix(logs.count)).map { $0.source + $0.translation } == logs)

        speech("取り消す内容", cue: UUID())
        try await eventually { translator.calls.count == 1 }
        model.clearCaption(); translator.complete("Must not return.")
        try await eventually { translator.active == 0 }
        precondition(model.sentenceReading.text.isEmpty && model.sentenceReading.previous.isEmpty)
        worker.cancel(); await worker.value
        print("PASS: \(language.rawValue) standard sentence display ignores legacy off preference, retains separate context and full logs, preserves capture/session on display switches, clears stale updates")
    }
}
