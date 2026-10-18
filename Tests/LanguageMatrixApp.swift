// Live integration harness: uses the production SwiftUI translation host and
// typed synthetic input. Never starts a microphone or captures another app.
import AppKit
import SwiftUI
import NaturalLanguage

@main enum LanguageMatrixApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = LanguageMatrixDelegate()
        app.delegate = delegate; app.setActivationPolicy(.regular); app.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor final class LanguageMatrixDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private let model = AppModel(glossary: GlossaryStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("quillo-empty-test-glossary")))
    private let examples: [CaptionLanguage: String] = [
        .japanese: "この授業は9時に始まります。明日は授業がありません。",
        .english: "This class starts at 9. There is no class tomorrow.",
        .chinese: "这节课9点开始。明天没有课。",
        .traditionalChinese: "這堂課9點開始。明天沒有課。"
    ]
    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 760, height: 800), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Quillo — 16通りの翻訳確認（マイク不使用）"
        window.contentView = NSHostingView(rootView: ControlView(model: model))
        window.center(); window.makeKeyAndOrderFront(nil)
        Task { await verify() }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    private func record(_ rows: [[String: String]]) {
        let data = try! JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
        try! data.write(to: URL(fileURLWithPath: "/private/tmp/quillo-caption-matrix.json"), options: .atomic)
    }
    private func verify() async {
        var rows: [[String: String]] = []
        model.clearCaption(); model.setCaptionMode(.bilingual)
        // Deliberately reuse one control view across all pairs. This catches
        // the cancelled SwiftUI session that unit-only translators cannot.
        for source in CaptionLanguage.allCases {
            for target in CaptionLanguage.allCases {
                model.sourceLanguage = source; model.targetLanguage = target
                model.languageChanged()
                let input = examples[source]!
                model.typedText = input; model.sendTypedCaption()
                let deadline = ContinuousClock.now.advanced(by: .seconds(20))
                while model.requiresTranslation && (model.translatedText.isEmpty || model.translationUpdating), ContinuousClock.now < deadline {
                    try? await Task.sleep(for: .milliseconds(100))
                    if model.liveTranslationFailed { break }
                }
                let output = model.requiresTranslation ? model.translatedText : model.sourceText
                let detected = NLLanguageRecognizer.dominantLanguage(for: output)?.rawValue ?? ""
                let scriptOK = !target.isChinese || target.normalizeScript(output) == output
                let languageOK: Bool
                switch target {
                case .english: languageOK = detected == "en"
                case .japanese: languageOK = detected == "ja"
                case .chinese, .traditionalChinese: languageOK = detected.hasPrefix("zh")
                }
                let passed = !output.isEmpty && output.contains("9") && scriptOK && languageOK && !model.translationUpdating
                rows.append(["source": source.rawValue, "target": target.rawValue, "input": input, "output": output,
                             "detected": detected, "result": passed ? "PASS" : "FAIL", "status": model.translationStatus])
                record(rows)
            }
        }
        window.title = "Quillo — 翻訳確認 \(rows.filter { $0["result"] == "PASS" }.count)/16"
        model.shutdown()
    }
}
