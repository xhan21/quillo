import AppKit
import SwiftUI
import Translation

@main enum EnglishReadingPreview {
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
        model.setReadableEnglish(true); model.setCaptionMode(.translationOnly)
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 960, height: 620), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Quillo — 英語字幕の比較（マイク不使用）"
        window.contentView = NSHostingView(rootView: ReadingPreviewView(model: model))
        window.center(); window.makeKeyAndOrderFront(nil)
        Task { await verify() }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { model.shutdown() }
    private func verify() async {
        let id = UUID()
        var rows: [[String: String]] = []
        let inputs = ["条件が真なら", "条件が真なら、結果は", "条件が真なら、結果は偽ではありません。"]
        model.isListening = true
        for (i, input) in inputs.enumerated() {
            model.speech.onText?(SpeechSnapshot(segmentID: id, text: input), i == inputs.count - 1)
            let deadline = ContinuousClock.now.advanced(by: .seconds(20))
            while (model.translatedText.isEmpty || model.translationUpdating), ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(50))
            }
            try? await Task.sleep(for: .milliseconds(700))
            rows.append(["input": input, "translation": model.translatedText, "display": model.visibleCaption.translation,
                         "result": !model.translatedText.isEmpty && !model.translationUpdating ? "PASS" : "FAIL"])
        }
        // Use the same production worker across a new utterance and a long sentence.
        model.typedText = "この授業では、学生が入力した情報をコンピューターがどのように処理して結果を表示するかを理解できるように、条件が真の場合と偽の場合の違いを、三つの具体的な例を比較しながら順番に説明します。"
        model.sendTypedCaption()
        let deadline = ContinuousClock.now.advanced(by: .seconds(20))
        while (model.translatedText.isEmpty || model.translationUpdating), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(50)) }
        let full = model.translatedText, presentation = model.captionPresentation
        let english = presentation.english!
        model.setReadableEnglish(false); let old = model.visibleCaption.translation; model.setReadableEnglish(true)
        let (_, lines) = CaptionViewport.lineBudget(showsSource: false, showsTranslation: true, style: model.appearance, height: model.captionLayoutSize.height)
        let budget = Double(lines) * CaptionTypesetting.lineHeight(model.appearance.translationFontSize)
        rows.append(["translation": full, "display": english.text, "legacyDisplay": old, "fontSize": "\(english.fontSize)",
                     "result": !full.isEmpty && !model.translationUpdating && full == english.text && english.height <= budget ? "PASS" : "FAIL"])
        let data = try! JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
        try! data.write(to: URL(fileURLWithPath: "/private/tmp/quillo-english-reading-check.json"), options: .atomic)
        window.title = "Quillo — 英語字幕の確認 \(rows.filter { $0["result"] == "PASS" }.count)/4（マイク不使用）"
    }
}
private struct ReadingPreviewView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("実際のApple翻訳で比較 · マイクは使用しません").font(.headline)
            Toggle("読みやすさ優先（オフで従来の表示）", isOn: Binding(get: { model.readableEnglish }, set: { model.setReadableEnglish($0) }))
            OverlayCaptionView(model: model).frame(width: 900, height: 260)
            Text("入力：" + model.sourceText).font(.system(size: 13))
            Text("翻訳全文：" + model.translatedText).font(.system(size: 13))
            Button("短い例（2文）を表示") { model.typedText = "この結果は真です。次に、三つの例を比較します。"; model.sendTypedCaption() }
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
