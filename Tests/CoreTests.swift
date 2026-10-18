import Foundation

@main enum CoreTests {
    static func main() {
        precondition(captionText("  こんにちは\n") == "こんにちは")
        let longText = "最初の文章。" + String(repeating: "👩🏽‍🏫授業で考えること。", count: 190) + "最後の文章。"
        precondition(captionText(longText) == longText, "Long captions must preserve the beginning, end and every Unicode character")
        precondition(captionText("\n  ") == "")
        let longBilingual = VisibleCaption(source: longText, translation: String(repeating: "Complete translated text. ", count: 190), translates: true, mode: .bilingual, ready: true)
        precondition(longBilingual.source == longText && longBilingual.translation.count > 180)
        precondition(clamp(-2, 0.15, 1) == 0.15)
        precondition(clamp(12, 0.15, 1) == 1)
        precondition(clamp(0.85, 0.15, 1) == 0.85)
        for sample in SampleCaption.examples {
            for language in CaptionLanguage.allCases { precondition(!sample.text(language).isEmpty) }
        }
        for ready in [true, false] {
            let pending = VisibleCaption(source: "原文を表示しない", translation: "", translates: true, mode: .translationOnly, ready: ready)
            precondition(pending.source.isEmpty && pending.translation.isEmpty && !pending.placeholder.isEmpty)
        }
        let translatedOnly = VisibleCaption(source: "こんにちは", translation: "Hello", translates: true, mode: .translationOnly, ready: true)
        precondition(translatedOnly.source.isEmpty && translatedOnly.translation == "Hello")
        let both = VisibleCaption(source: "こんにちは", translation: "Hello", translates: true, mode: .bilingual, ready: true)
        precondition(both.source == "こんにちは" && both.translation == "Hello")
        let untranslated = VisibleCaption(source: "こんにちは", translation: "古い翻訳", translates: false, mode: .translationOnly, ready: false)
        precondition(untranslated.source == "こんにちは" && untranslated.translation.isEmpty)
        print("PASS: full long Unicode captions, settings bounds, sample coverage, translation-only never reveals original while pending, bilingual display")
    }
}
