import Foundation

// Hand-authored, generic vocabulary. Never include personal course material here.
// Conversation phrases are recognition hints, not forced translations or ASR replacements.
enum CommonVocabulary {
    static let conversation: [String] = [
        "大丈夫です", "なるほど", "たとえば", "つまり", "ちなみに", "そうですね",
        "わかりました", "もう一度お願いします", "少し待ってください", "ありがとうございます",
        "よろしくお願いします", "すみません"
    ]
    static let glossary = MaterialGlossary(id: "quillo-common-v1", name: "共通辞書", entries: [
        entry("声色", "tone of voice", "语气", "語氣", ["こわいろ"]),
        entry("ローカルLLM", "local LLM", "本地大语言模型", "本地大型語言模型", ["ローカルエルエルエム", "ローカル LLM"]),
        entry("大規模言語モデル", "large language model", "大语言模型", "大型語言模型", ["LLM", "エルエルエム"]),
        entry("人工知能", "artificial intelligence", "人工智能", "人工智慧", ["AI", "エーアイ"]),
        entry("生成AI", "generative AI", "生成式人工智能", "生成式人工智慧", ["生成エーアイ", "生成 AI"]),
        entry("プロンプト", "prompt", "提示词", "提示詞"),
        entry("音声認識", "speech recognition", "语音识别", "語音辨識"),
        entry("文字起こし", "transcription", "转写", "轉寫", ["文字おこし"]),
        entry("読み上げ", "text-to-speech", "文本朗读", "文字朗讀", ["読みあげ"]),
        entry("字幕", "captions", "字幕", "字幕"),
        entry("翻訳", "translation", "翻译", "翻譯"),
        entry("要約", "summary", "摘要", "摘要"),
        entry("文脈", "context", "语境", "語境"),
        entry("ニュアンス", "nuance", "细微差别", "細微差異"),
        entry("抑揚", "intonation", "语调", "語調", ["よくよう"]),
        entry("相づち", "backchannel response", "附和语", "附和語", ["あいづち", "相槌"]),
        entry("言い回し", "phrasing", "措辞", "措辭", ["言いまわし"]),
        entry("聞き取り", "listening comprehension", "听力理解", "聽力理解", ["聞きとり"]),
        entry("言い換え", "paraphrase", "改述", "改述", ["言いかえ"]),
        entry("句読点", "punctuation", "标点符号", "標點符號", ["くとうてん"]),
        entry("誤字", "typo", "错字", "錯字"),
        entry("脱字", "omitted character", "漏字", "漏字"),
        entry("オフライン", "offline", "离线", "離線"),
        entry("オンライン", "online", "在线", "線上"),
        entry("再起動", "restart", "重新启动", "重新啟動")
    ])
    // Keep ordinary prose free to translate naturally. Only these specific terms
    // get fixed translation spellings; all entries remain recognition/AI hints.
    static let translationGlossary = MaterialGlossary(id: "quillo-common-translation-v1", name: "共通用語", entries:
        glossary.entries.filter { ["声色", "ローカルLLM", "大規模言語モデル", "人工知能", "生成AI", "プロンプト"].contains($0.terms["ja"] ?? "") })
    private static func entry(_ ja: String, _ en: String, _ simplified: String, _ traditional: String,
                              _ readings: [String] = []) -> GlossaryEntry {
        var aliases = readings.isEmpty ? [:] : ["ja": readings]
        let abbreviations = readings.filter { $0 == "AI" || $0 == "LLM" }
        if !abbreviations.isEmpty {
            for language in ["en", "zh-Hans", "zh-Hant"] { aliases[language] = abbreviations }
        }
        return .init(terms: ["ja": ja, "en": en, "zh-Hans": simplified, "zh-Hant": traditional], aliases: aliases)
    }
}
