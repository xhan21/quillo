import Foundation

enum CaptionDisplayMode: String, CaseIterable, Identifiable {
    case translationOnly, bilingual
    var id: String { rawValue }
    var name: String { self == .translationOnly ? "翻訳文のみ" : "原文 ＋ 翻訳文" }
}

struct VisibleCaption {
    let source: String
    let translation: String
    let placeholder: String
    init(source: String, translation: String, translates: Bool, mode: CaptionDisplayMode, ready: Bool, waiting: String? = nil) {
        self.source = !translates || mode == .bilingual ? source : ""
        self.translation = translates ? translation : ""
        if self.source.isEmpty && self.translation.isEmpty {
            placeholder = waiting ?? (source.isEmpty ? "字幕を待っています…" : ready ? "翻訳しています…" : "翻訳を準備してください")
        } else {
            placeholder = ""
        }
    }
}

enum CaptionLanguage: String, CaseIterable, Identifiable {
    case japanese = "ja", english = "en", chinese = "zh-Hans", traditionalChinese = "zh-Hant"
    static let speechInputLanguages: [CaptionLanguage] = [.japanese, .english]
    var supportsSpeechInput: Bool { Self.speechInputLanguages.contains(self) }
    var id: String { rawValue }
    var name: String { switch self { case .japanese: return "日本語"; case .english: return "English"; case .chinese: return "中文（簡体字）"; case .traditionalChinese: return "中文（繁體字）" } }
    var speechLocale: String { switch self { case .japanese: return "ja-JP"; case .english: return "en-US"; case .chinese: return "zh-CN"; case .traditionalChinese: return "zh-TW" } }
    var ocrLocale: String { switch self { case .chinese, .traditionalChinese: return rawValue; default: return speechLocale } }
    var isChinese: Bool { self == .chinese || self == .traditionalChinese }
    var dictationName: String { switch self {
        case .japanese: return "日本語（日本）"
        case .english: return "英語（アメリカ合衆国）"
        case .chinese: return "中国語（普通話 - 中国本土）"
        case .traditionalChinese: return "中国語（普通話 - 台湾）"
    } }
    func normalizeScript(_ text: String) -> String {
        guard isChinese else { return text }
        let transform = StringTransform(self == .chinese ? "Traditional-Simplified" : "Simplified-Traditional")
        return text.applyingTransform(transform, reverse: false) ?? text
    }
}

struct SampleCaption {
    let japanese: String
    let english: String
    let chinese: String
    let traditionalChinese: String
    func text(_ language: CaptionLanguage) -> String {
        switch language { case .japanese: return japanese; case .english: return english; case .chinese: return chinese; case .traditionalChinese: return traditionalChinese }
    }
    static let examples = [
        SampleCaption(japanese: "AIに任せること。人が考えること。", english: "What we leave to AI. What we think through ourselves.", chinese: "哪些交给人工智能，哪些由我们自己思考。", traditionalChinese: "哪些交給人工智慧，哪些由我們自己思考。"),
        SampleCaption(japanese: "今日は、身近なAIとの付き合い方を考えます。", english: "Today, let’s think about how we use AI in everyday life.", chinese: "今天，我们来思考如何与日常生活中的人工智能相处。", traditionalChinese: "今天，我們來思考如何與日常生活中的人工智慧相處。"),
        SampleCaption(japanese: "みなさんは今日、どんな場面でAIを使いましたか？", english: "Where have you used AI today?", chinese: "大家今天在哪些场景中使用了人工智能？", traditionalChinese: "大家今天在哪些情境中使用了人工智慧？"),
        SampleCaption(japanese: "自然な文章でも、内容が正しいとは限りません。", english: "A text that reads naturally is not necessarily accurate.", chinese: "读起来很自然的文章，内容不一定正确。", traditionalChinese: "讀起來很自然的文章，內容不一定正確。")
    ]
}

enum CaptionCorrectionState: Equatable {
    case original, queued, checking, corrected, unchanged, unavailable
    var label: String {
        switch self {
        case .original, .unavailable: return "入力そのまま"
        case .queued: return "補正待ち"
        case .checking: return "原文AI補正中"
        case .corrected: return "原文AI補正済み"
        case .unchanged: return "AI確認・変更なし"
        }
    }
    var symbol: String {
        switch self {
        case .original, .unavailable: return "text.alignleft"
        case .queued, .checking: return "clock"
        case .corrected: return "checkmark.seal.fill"
        case .unchanged: return "checkmark.circle"
        }
    }
    var detail: String {
        switch self {
        case .original: return "入力文をそのまま表示しています。"
        case .queued: return "入力文を表示しながら、AIの順番を待っています。"
        case .checking: return "入力文を表示しながら、AIが補正しています。"
        case .corrected: return "AIで補正した入力文を表示し、翻訳にも反映します。補正前後は下で確認できます。"
        case .unchanged: return "AIが確認しましたが、入力文は変更していません。"
        case .unavailable: return "補正を採用できなかったため、入力文をそのまま表示しています。"
        }
    }
}

struct TranscriptLine: Identifiable {
    let id: UUID
    let time: Date
    var source: String
    var translation: String
    let kind: String
    var translationIncomplete = false
    var correctionState: CaptionCorrectionState = .original
    var sourceBeforeCorrection: String?
    var sourceCorrected: Bool {
        get { correctionState == .corrected }
        set { correctionState = newValue ? .corrected : .original }
    }
}

struct TranslationJob: Sendable, Equatable {
    let cueID: UUID
    let revision: Int
    let generation: Int
    let text: String
}

func captionText(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
}

func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
    min(max(value, lower), upper)
}
