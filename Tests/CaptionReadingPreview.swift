import AppKit
import SwiftUI
import Translation

@main enum CaptionReadingPreview {
    @MainActor static func main() {
        let app = NSApplication.shared, delegate = ReadingPreviewDelegate()
        app.delegate = delegate; app.setActivationPolicy(.regular); app.run()
        withExtendedLifetime(delegate) {}
    }
}
@MainActor final class ReadingPreviewDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private let model = AppModel(glossary: GlossaryStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("quillo-empty-reading-glossary")))
    func applicationDidFinishLaunching(_ notification: Notification) {
        model.clearCaption(); model.appearance = CaptionAppearance()
        model.appearance.automaticHeight = false; model.appearance.height = 260
        model.appearance.translationFontSize = 38
        model.setCaptionMode(.translationOnly)
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 960, height: 620), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Quillo — 英語・中国語字幕の確認（マイク不使用）"
        window.contentView = NSHostingView(rootView: ReadingPreviewView(model: model))
        window.center(); window.makeKeyAndOrderFront(nil)
        Task { await verify() }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { model.shutdown() }
    private func verify() async {
        var rows: [[String: String]] = []
        let pairs: [(CaptionLanguage, CaptionLanguage)] = [(.japanese, .english), (.japanese, .chinese), (.english, .chinese), (.english, .traditionalChinese), (.japanese, .traditionalChinese)]
        for (source, target) in pairs {
            model.targetLanguage = target; model.setSpeechLanguage(source); model.languageChanged()
            model.setCaptionMode(.translationOnly)
            let id = UUID()
            let inputs = source == .japanese
                ? ["条件が真なら", "条件が真なら、結果は", "条件が真なら、結果は偽ではありません。"]
                : ["If the condition", "If the condition is true, the result", "If the condition is true, the result is not false."]
            model.isListening = true // Simulated recognition callbacks; no microphone capture.
            for (i, input) in inputs.enumerated() {
                model.speech.onText?(SpeechSnapshot(segmentID: id, text: input), i == inputs.count - 1)
                await waitForTranslation()
                try? await Task.sleep(for: .milliseconds(700))
                rows.append(["pair": model.languagePairLabel, "input": input, "translation": model.translatedText, "display": model.visibleCaption.translation,
                             "result": !model.translatedText.isEmpty && !model.translationUpdating && model.captionPresentation.reading != nil ? "PASS" : "FAIL"])
            }
            model.isListening = false
            model.typedText = source == .japanese
                ? "この授業では、学生が入力した情報をコンピューターがどのように処理して結果を表示するかを理解できるように、条件が真の場合と偽の場合の違いを、三つの具体的な例を比較しながら順番に説明します。"
                : "In this lesson, we will compare three specific examples of true and false conditions so that students can understand how a computer processes the information they enter and displays the results."
            model.sendTypedCaption()
            await waitForTranslation()
            let full = model.translatedText, reading = model.captionPresentation.reading
            let budget = model.captionLayoutSize.height - 76
            rows.append(["pair": model.languagePairLabel, "translation": full, "display": reading?.text ?? "", "fontSize": "\(reading?.fontSize ?? 0)",
                         "result": !full.isEmpty && !model.translationUpdating && full == reading?.text && (reading?.height ?? .infinity) <= budget ? "PASS" : "FAIL"])
        }
        for language in [CaptionLanguage.english, .chinese, .traditionalChinese] {
            model.targetLanguage = language; model.setSpeechLanguage(.japanese); model.languageChanged()
            model.clearCaption()
            var translations: [String] = []
            for input in ["入力した情報を処理します。", "結果を画面に表示します。", "次に三つの例を比較します。"] {
                model.typedText = input; model.sendTypedCaption(); await waitForTranslation()
                translations.append(model.translatedText)
            }
            let reading = model.captionPresentation.reading
            rows.append(["pair": model.languagePairLabel, "history": reading?.history.joined(separator: " | ") ?? "", "display": reading?.text ?? "",
                "result": reading?.history == Array(translations.prefix(2)) && reading?.text == translations.last ? "PASS" : "FAIL"])
        }
        let data = try! JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
        try! data.write(to: URL(fileURLWithPath: "/private/tmp/quillo-caption-reading-check.json"), options: .atomic)
        window.title = "Quillo — 字幕の確認 \(rows.filter { $0["result"] == "PASS" }.count)/\(rows.count)（マイク不使用）"
    }
    private func waitForTranslation() async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(25))
        while (model.translatedText.isEmpty || model.translationUpdating), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }
}
private struct ReadingPreviewView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("実際のApple翻訳で表示を確認 · マイクは使用しません").font(.headline)
            OverlayCaptionView(model: model).frame(width: 900, height: 260)
            Text("入力：" + model.sourceText).font(.system(size: 13))
            Text("翻訳全文：" + model.translatedText).font(.system(size: 13))
            HStack {
                ForEach([CaptionLanguage.chinese, .traditionalChinese]) { language in
                    Button(language.name + "の例（3文）") {
                        model.targetLanguage = language; model.setSpeechLanguage(.japanese); model.languageChanged()
                        model.typedText = "この結果は真です。条件を変えると結果も変わります。次に、三つの例を比較します。"; model.sendTypedCaption()
                    }
                }
            }
            Text(model.translationStatus).font(.caption)
        }.padding(24).frame(width: 960, height: 620).background(Color.kotobaPaper)
        .background {
            if let configuration = model.translationConfiguration {
                ReadingTranslationHost(model: model, configuration: configuration, id: model.translationSessionID).id(model.translationSessionID)
            }
        }
    }
}
private struct ReadingTranslationHost: View {
    let model: AppModel
    let configuration: TranslationSession.Configuration
    let id: UUID
    var body: some View {
        Color.clear.frame(width: 1, height: 1).translationTask(configuration) { await model.runTranslation($0, sessionID: id) }
    }
}
