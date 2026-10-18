import AppKit
import NaturalLanguage

@main enum LanguageCoverageTests {
    @MainActor static func main() async throws {
        setbuf(stdout, nil); _ = NSApplication.shared
        // Recognition callbacks exercise every mode without microphone access.
        let model = AppModel(glossary: GlossaryStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
        defer { model.shutdown() }
        for source in CaptionLanguage.allCases {
            for target in CaptionLanguage.allCases {
                model.sourceLanguage = source; model.targetLanguage = target; model.languageChanged()
                model.setCaptionMode(.bilingual)
                let text = source.normalizeScript("資訊與電腦")
                if source == target || model.convertsChineseScript {
                    model.isListening = true
                    model.speech.onText?(.init(segmentID: UUID(), text: text), false)
                    precondition(model.sourceText == text)
                    if source != target {
                        precondition(model.translatedText == target.normalizeScript(text))
                        precondition(model.pendingTranslationCount == 0 && model.translationReady)
                    } else { precondition(!model.requiresTranslation) }
                    model.setCaptionMode(nil); model.setCaptionMode(.translationOnly)
                    precondition(model.isListening && model.sourceText == text)
                    if source != target { precondition(!model.translationStatus.contains("原文のみ")) }
                    model.stopMic()
                } else {
                    precondition(model.translationConfiguration?.source?.minimalIdentifier == Locale.Language(identifier: source.rawValue).minimalIdentifier)
                    precondition(model.translationConfiguration?.target?.minimalIdentifier == Locale.Language(identifier: target.rawValue).minimalIdentifier)
                    let old = model.translationSessionID
                    model.retryTranslation()
                    precondition(model.translationSessionID != old, "A retry needs a fresh SwiftUI host")
                }
            }
        }
        model.sourceLanguage = .chinese; model.targetLanguage = .english; model.languageChanged()
        model.translationReady = true
        let readySession = model.translationSessionID
        model.setCaptionMode(nil); model.setCaptionMode(.bilingual)
        precondition(model.translationSessionID == readySession && model.translationStatus.contains("翻訳の準備ができました"))
        // A delayed worker from an old configuration must not claim the new queue.
        await model.runTranslationWorker(expectedEpoch: -1, prepare: { preconditionFailure("Stale worker prepared") }, translate: { _ in preconditionFailure("Stale worker translated") })
        print("PASS: 16 language routes, direct Chinese script conversion, original-only mode, fresh retry identity, stale worker rejection")

        guard CommandLine.arguments.contains("--live") else { return }
        let service = LocalSlideSummarizer()
        let size = CGSize(width: 1000, height: 650)
        var rows: [[String: String]] = []
        for source in CaptionLanguage.allCases {
            let canvas = SlideDemoCanvas(frame: CGRect(origin: .zero, size: size), language: source)
            let rep = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds)!
            canvas.cacheDisplay(in: canvas.bounds, to: rep)
            let analysis = try SlideAnalyzer.analyze(image: rep.cgImage!, size: size, language: source, ignored: [], regions: [CGRect(x: 0.04, y: 0.04, width: 0.61, height: 0.70)], buildOccupancy: false)
            let text = analysis.blocks.map(\.text).joined(separator: "\n")
            precondition(analysis.blocks.count >= 3, "Read the title and both body paragraphs in every language")
            for target in CaptionLanguage.allCases {
                print("LIVE summary \(source.rawValue) -> \(target.rawValue)")
                let display = SlideSummaryModel(generate: { try await service.summarize($0) })
                display.setSourceLanguage(source)
                display.resize(CGSize(width: 348, height: 210))
                display.update(source: text, target: target, active: true)
                let deadline = ContinuousClock.now.advanced(by: .seconds(100))
                while display.busy && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(100)) }
                let output = display.text
                let detected = NLLanguageRecognizer.dominantLanguage(for: output)?.rawValue ?? ""
                let languageOK = target == .english ? detected == "en" : target == .japanese ? detected == "ja" : detected.hasPrefix("zh")
                let passed = !output.isEmpty && !display.busy && languageOK && target.normalizeScript(output) == output
                    && SlidePanelTypesetting.fit(output, size: CGSize(width: 348, height: 210), preferredFontSize: 20).pages.count == 1
                rows.append(["source": source.rawValue, "target": target.rawValue, "ocr": text, "output": output, "result": passed ? "PASS" : "FAIL", "status": display.status])
                try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/private/tmp/quillo-summary-matrix.json"), options: .atomic)
                print("\(passed ? "PASS" : "FAIL"): \(output.isEmpty ? display.status : output)")
                display.clear()
            }
        }
        precondition(rows.allSatisfy { $0["result"] == "PASS" }, "Inspect /tmp/quillo-summary-matrix.json")
    }
}
