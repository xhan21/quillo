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
    private var recognition: SFSpeechRecognitionTask?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var finished = false
    private var failure = ""
    private var callbacks = 0
    private var recognitionIDs: Set<UUID> = []
    private var rawSnapshots: [String] = []
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
    func applicationWillTerminate(_ notification: Notification) { recognition?.cancel(); request?.endAudio(); model.shutdown() }
    private func verify() async {
        do {
            let deadline = ContinuousClock.now.advanced(by: .seconds(30))
            while !model.translationReady, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(100)) }
            guard model.translationReady else { throw NSError(domain: "Translation preparation", code: 1) }
            let url = Bundle.main.url(forResource: "history-speech-fixture", withExtension: "aiff")!
            let file = try AVAudioFile(forReading: url)
            let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))!
            guard recognizer.supportsOnDeviceRecognition else { throw NSError(domain: "On device speech unavailable", code: 1) }
            let request = SFSpeechAudioBufferRecognitionRequest(); self.request = request
            request.requiresOnDeviceRecognition = true; request.shouldReportPartialResults = true; request.addsPunctuation = true
            let taskID = UUID()
            model.isListening = true
            recognition = recognizer.recognitionTask(with: request) { [weak self] result, error in
                let snapshot = result.map { SpeechSnapshot(segmentID: taskID, text: $0.bestTranscription.formattedString, words: $0.bestTranscription.segments.map { SpeechWord(range: $0.substringRange, timestamp: $0.timestamp, duration: $0.duration) }) }
                let final = result?.isFinal ?? false, message = error?.localizedDescription
                Task { @MainActor in
                    guard let self else { return }
                    if let snapshot {
                        self.callbacks += 1; self.recognitionIDs.insert(snapshot.segmentID)
                        self.rawSnapshots.append(snapshot.text); self.model.speech.onText?(snapshot, final)
                    }
                    if final { self.finished = true }
                    if let message { self.failure = message; self.finished = true }
                }
            }
            while file.framePosition < file.length && !finished {
                let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.processingFormat.sampleRate * 0.1))!
                try file.read(into: buffer); request.append(buffer)
                try await Task.sleep(for: .milliseconds(100))
            }
            request.endAudio()
            for _ in 0..<150 where !finished { try await Task.sleep(for: .milliseconds(100)) }
            model.isListening = false
            for _ in 0..<200 where model.logs.contains(where: { $0.translationIncomplete || $0.translation.isEmpty }) { try await Task.sleep(for: .milliseconds(100)) }
        } catch { failure = error.localizedDescription }
        let source = model.logs.map(\.source), translations = model.logs.map(\.translation)
        let expectedFirst = Bundle.main.url(forResource: "expected-first-word", withExtension: "txt")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }.map(captionText) ?? ""
        let openingPreserved = expectedFirst.isEmpty || (rawSnapshots.contains { $0.hasPrefix(expectedFirst) } && source.first?.hasPrefix(expectedFirst) == true)
        let passed = failure.isEmpty && finished && callbacks > 5 && recognitionIDs.count == 1 && source.count >= 3
            && model.captionPresentation.sourceReading?.history.count == 2 && model.captionPresentation.reading?.history.count == 2
            && model.logs.allSatisfy { !$0.translationIncomplete && !$0.translation.isEmpty }
            && openingPreserved
        let report: [String: Any] = ["passed": passed, "error": failure, "callbacks": callbacks, "recognitionTasks": recognitionIDs.count,
            "source": source, "translations": translations, "sourceHistory": model.sourceReading.history, "translationHistory": model.sentenceReading.history,
            "currentSource": model.visibleCaption.source, "currentTranslation": model.visibleCaption.translation,
            "expectedFirstWord": expectedFirst, "openingWordPreserved": openingPreserved, "rawRecognition": rawSnapshots]
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
