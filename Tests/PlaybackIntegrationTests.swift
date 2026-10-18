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
        try await modeSwitching()
        print("PASS: synchronous original update (\(updateTime)), partial translation progress, coalescing, no duplicated finals, no stale overwrite, live priority + final logs, errors recover, clear cancels, full logs, one translation in flight")
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
        try await eventually { model.translatedText == "Keep listening" && !model.translationUpdating }
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
}
