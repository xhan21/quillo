import AppKit
import SwiftUI
import Speech
import AVFoundation
import Translation

// Synthetic audio -> real on-device recognition -> production caption pipeline
// -> real Apple Translation. This never opens the microphone.
@main enum SpeechHistoryPreview {
    @MainActor static func main() {
        let app = NSApplication.shared, delegate = SpeechHistoryDelegate()
        app.delegate = delegate; app.setActivationPolicy(.regular); app.run()
        withExtendedLifetime(delegate) {}
    }
}
@MainActor final class SpeechHistoryDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel(glossary: GlossaryStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("quillo-empty-speech-check")))
    private var window: NSWindow!
    private var stream: SpeechRecognitionStream?
    private var audioEnded = false
    private var handoffCheck = false
    private var finished = false
    private var failure = ""
    private var callbacks = 0
    private var recognitionIDs: Set<UUID> = []
    private var rawSnapshots: [String] = []
    private var events: [[String: Any]] = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        model.clearCaption(); model.setSpeechLanguage(.japanese); model.targetLanguage = .english; model.languageChanged()
        model.setCaptionCorrection(false)
        model.historySettings = CaptionHistorySettings(); model.appearance = CaptionAppearance()
        model.setCaptionMode(.bilingual)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 620), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Quillo — 合成音声から履歴を確認（マイク不使用）"
        window.contentView = NSHostingView(rootView: SpeechHistoryView(model: model))
        window.center(); window.makeKeyAndOrderFront(nil)
        model.prepareTranslation()
        Task { await verify() }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { stream?.stop(); model.shutdown() }
    private func verify() async {
        do {
            let deadline = ContinuousClock.now.advanced(by: .seconds(30))
            while !model.translationReady, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(100)) }
            guard model.translationReady else { throw NSError(domain: "Translation preparation", code: 1) }
            let url = Bundle.main.url(forResource: "history-speech-fixture", withExtension: "aiff")!
            let file = try AVAudioFile(forReading: url)
            let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))!
            guard recognizer.supportsOnDeviceRecognition else { throw NSError(domain: "On device speech unavailable", code: 1) }
            let secondURL = Bundle.main.url(forResource: "handoff-speech-fixture", withExtension: "aiff")
            handoffCheck = secondURL != nil
            // Default mode deliberately retains one task to exercise cumulative
            // callbacks. Handoff mode uses the production quiet rollover too.
            let stream = SpeechRecognitionStream(recognizer: recognizer, pauseRollover: handoffCheck); self.stream = stream
            stream.phrases = { ["大丈夫", "ちゃんと"] }
            model.isListening = true
            stream.onText = { [weak self] snapshot, final in
                guard let self else { return }
                self.callbacks += 1; self.recognitionIDs.insert(snapshot.segmentID)
                self.rawSnapshots.append(snapshot.text)
                self.events.append(["id": snapshot.segmentID.uuidString, "text": snapshot.text, "final": final, "time": ProcessInfo.processInfo.systemUptime,
                    "words": snapshot.words.map { ["start": $0.timestamp, "duration": $0.duration, "offset": $0.range.location] }])
                self.model.speech.onText?(snapshot, final)
                if final && self.audioEnded { self.finished = true }
            }
            stream.onFailure = { [weak self] message in self?.failure = message; self?.finished = true }
            stream.start()
            var files = [file]
            if let secondURL { files.append(try AVAudioFile(forReading: secondURL)) }
            for (index, input) in files.enumerated() {
                // Start feeding the next phrase immediately while the old
                // request drains. Its opening buffer must survive the handoff.
                if index > 0 { stream.rotate() }
                while input.framePosition < input.length && !finished {
                    let buffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: AVAudioFrameCount(input.processingFormat.sampleRate * 0.1))!
                    try input.read(into: buffer); stream.audio.append(buffer)
                    try await Task.sleep(for: .milliseconds(100))
                }
            }
            // A live microphone keeps supplying silence after speech. Include
            // that tail instead of ending the file on the final phoneme.
            for _ in 0..<12 {
                let silence = AVAudioPCMBuffer(pcmFormat: files.last!.processingFormat, frameCapacity: AVAudioFrameCount(files.last!.processingFormat.sampleRate * 0.1))!
                silence.frameLength = silence.frameCapacity
                for b in UnsafeMutableAudioBufferListPointer(silence.mutableAudioBufferList) { if let data = b.mData { memset(data, 0, Int(b.mDataByteSize)) } }
                stream.audio.append(silence)
                try await Task.sleep(for: .milliseconds(100))
            }
            audioEnded = true
            if events.last?["final"] as? Bool == true { finished = true }
            else { stream.rotate() }
            for _ in 0..<150 where !finished { try await Task.sleep(for: .milliseconds(100)) }
            stream.stop()
            model.isListening = false
            for _ in 0..<200 where model.logs.contains(where: { $0.translationIncomplete || $0.translation.isEmpty }) { try await Task.sleep(for: .milliseconds(100)) }
        } catch { failure = error.localizedDescription }
        let source = model.logs.map(\.source), translations = model.logs.map(\.translation)
        let expectedFirst = Bundle.main.url(forResource: "expected-first-word", withExtension: "txt")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }.map(captionText) ?? ""
        let openingPreserved = expectedFirst.isEmpty || (rawSnapshots.contains { $0.hasPrefix(expectedFirst) } && source.first?.hasPrefix(expectedFirst) == true)
        let handoffOpeningPreserved = !handoffCheck || (["大丈夫", "ちゃんと", "最後"].allSatisfy { word in source.contains { $0.hasPrefix(word) } })
        let completePhrases = !handoffCheck || ["大丈夫です", "ちゃんと聞こえます", "最後に使い心地を比較します"].allSatisfy { expected in
            source.contains { $0.filter { !$0.isPunctuation && !$0.isWhitespace } == expected }
        }
        let taskCountCorrect = handoffCheck ? recognitionIDs.count >= 2 : recognitionIDs.count == 1
        let passed = failure.isEmpty && finished && callbacks > 5 && taskCountCorrect && source.count >= 3
            && model.captionPresentation.sourceReading?.history.count == 2 && model.captionPresentation.reading?.history.count == 2
            && model.logs.allSatisfy { !$0.translationIncomplete && !$0.translation.isEmpty }
            && openingPreserved && handoffOpeningPreserved && completePhrases
        let report: [String: Any] = ["passed": passed, "error": failure, "callbacks": callbacks, "recognitionTasks": recognitionIDs.count,
            "source": source, "translations": translations, "sourceHistory": model.sourceReading.history, "translationHistory": model.sentenceReading.history,
            "currentSource": model.visibleCaption.source, "currentTranslation": model.visibleCaption.translation,
            "completePhrases": completePhrases, "handoffCheck": handoffCheck, "handoffOpeningPreserved": handoffOpeningPreserved, "expectedFirstWord": expectedFirst, "openingWordPreserved": openingPreserved, "rawRecognition": rawSnapshots, "events": events]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: "/private/tmp/quillo-speech-history-check.json"), options: .atomic)
        }
        window.title = "Quillo — 合成音声の履歴確認 \(passed ? "PASS" : "FAIL")（マイク不使用）"
    }
}
struct SpeechHistoryView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading) {
            Text("合成した授業音声 → 音声認識 → 翻訳 → 現在文と履歴").font(.headline)
            Text("マイクは使いません。字幕・翻訳は本体と同じ処理です。").font(.caption)
            OverlayCaptionView(model: model).frame(height: model.captionLayoutSize.height)
            Text("認識した区切り：\(model.logs.count)").font(.caption)
        }.padding(24).frame(width: 960).background(Color.kotobaPaper)
            .background {
                if let configuration = model.translationConfiguration {
                    SpeechCheckTranslationHost(model: model, configuration: configuration, sessionID: model.translationSessionID).id(model.translationSessionID)
                }
            }
    }
}

private struct SpeechCheckTranslationHost: View {
    let model: AppModel
    let configuration: TranslationSession.Configuration
    let sessionID: UUID
    var body: some View {
        Color.clear.frame(width: 1, height: 1).translationTask(configuration) { await model.runTranslation($0, sessionID: sessionID) }
    }
}
