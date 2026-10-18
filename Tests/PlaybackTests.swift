import AppKit

@main enum PlaybackTests {
    static func main() {
        let original = "最初の文です。" + String(repeating: "👩🏽‍🏫身近な道具を観察し、使いやすさを考えましょう。", count: 12) + "最後の文です。"
        let translated = "The first sentence. " + String(repeating: "Explore everyday tools, then share your ideas with the class. ", count: 10) + "The last sentence."
        for width in [320.0, 720, 1400] {
            for font in [14.0, 38, 90] {
                var style = CaptionAppearance(); style.sourceFontSize = font; style.translationFontSize = 104 - font
                let minimum = ceil((76 + CaptionTypesetting.lineHeight(font, weight: .medium) + CaptionTypesetting.lineHeight(style.translationFontSize)) / 10) * 10
                for height in [minimum, 600] {
                    let visible = CaptionViewport.latest(source: original, translation: translated, showsSource: true, showsTranslation: true, style: style, width: width, height: height)
                    precondition(original.hasSuffix(visible.source) && translated.hasSuffix(visible.translation), "Only layout tails, no ellipsis or changed content")
                    precondition(!visible.source.isEmpty && !visible.translation.isEmpty)
                    let caption = VisibleCaption(source: visible.source, translation: visible.translation, translates: true, mode: .bilingual, ready: true)
                    precondition(CaptionTypesetting.naturalHeight(caption: caption, style: style, width: width) <= height, "Both latest language blocks must fit")
                }
            }
        }
        let short = "短い字幕です。👩🏽‍🏫"
        precondition(CaptionViewport.tail(short, size: 20, width: 600, lines: 2, weight: .medium) == short)
        for text in ["a\nb\nc\nd", "家族👨‍👩‍👧‍👦 e\u{301} 日本語。\n" + translated, String(repeating: "長文", count: 3000)] {
            let tail = CaptionViewport.tail(text, size: 31, width: 600, lines: 2, weight: .medium)
            precondition(text.hasSuffix(tail) && !tail.isEmpty)
            precondition(CaptionTypesetting.lineCount(tail, size: 31, width: 600, weight: .medium) <= 2)
        }
        var mailbox = TranslationMailbox()
        let old = UUID(), live = UUID()
        mailbox.submit(TranslationJob(cueID: old, revision: 1, generation: 0, text: "previous final"))
        mailbox.preferredID = live
        for revision in 1...1000 { mailbox.submit(TranslationJob(cueID: live, revision: revision, generation: 0, text: "live \(revision)")) }
        precondition(mailbox.count == 2, "Intermediate recognition must not build a translation backlog")
        precondition(mailbox.takeNext()?.text == "live 1000", "Prioritize the newest live hypothesis")
        precondition(mailbox.takeNext()?.text == "previous final", "Retain final transcript translation")
        precondition(mailbox.takeNext() == nil)
        mailbox.submit(TranslationJob(cueID: live, revision: 4, generation: 0, text: "newer"))
        mailbox.submit(TranslationJob(cueID: live, revision: 2, generation: 0, text: "obsolete"))
        precondition(mailbox.takeNext()?.revision == 4)
        mailbox.removeAll(); precondition(mailbox.isEmpty)
        print("PASS: live line window fits widths/fonts/heights, exact Unicode suffixes, short text intact, coalescing 1000 hypotheses, live priority, retained final jobs")
    }
}
