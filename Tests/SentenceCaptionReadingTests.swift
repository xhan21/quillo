import AppKit

@main enum SentenceCaptionReadingTests {
    static func main() {
        var reader = SentenceCaptionReading()
        reader.begin(UUID(), now: 10)
        reader.receive("If the condition", now: 10)
        precondition(reader.text == "If the condition", "First translation is immediate")
        for i in 1...100 { reader.receive("If the condition is true, result \(i)", now: 10.1 + Double(i) / 1000) }
        precondition(reader.text == "If the condition" && reader.nextWakeup == 10.65, "Continuous partials cannot postpone the fixed update deadline")
        reader.tick(now: 10.66)
        precondition(reader.text == "If the condition is true, result 100", "Only the newest pending result is displayed")
        reader.receive("If the condition is true, the result is not false.", now: 10.7, final: true)
        precondition(reader.text.hasSuffix("not false.") && reader.nextWakeup == nil, "Final corrections appear immediately")
        reader.begin(UUID(), now: 11)
        precondition(reader.text.isEmpty && reader.previous == "If the condition is true, the result is not false.")
        reader.receive("Next, compare", now: 11.01)
        precondition(reader.text == "Next, compare" && !reader.previous.isEmpty)
        reader.tick(now: 600); precondition(!reader.previous.isEmpty && reader.nextWakeup == nil, "History does not disappear while students read")
        reader.begin(UUID(), now: 17)
        precondition(reader.history == ["If the condition is true, the result is not false.", "Next, compare"], "Recognized phrases without punctuation also remain available")
        reader.receive("A positive claim", now: 17)
        reader.receive("A corrected claim", now: 17.1)
        reader.flush(now: 17.11)
        precondition(reader.text == "A corrected claim" && reader.nextWakeup == nil)

        let sentences = SentenceCaptionLayout.sentences("Dr. Smith uses 3.14 as an approximation. It is not exact.")
        precondition(sentences.count == 2 && sentences[0].hasPrefix("Dr. Smith") && sentences[0].contains("3.14"), "Sentence parsing preserves common abbreviations and decimals")
        let sentence = "If the condition is true, the computer processes the input and displays the result."
        let fitted = SentenceCaptionLayout.layout(text: sentence, previous: "", fontSize: 38, width: 750, height: 95)
        precondition(fitted.text == sentence && fitted.fontSize < 38 && fitted.fontSize >= 18 && fitted.height <= 95, "Fit the complete conditional sentence before dropping any beginning")
        let paired = SentenceCaptionLayout.layout(text: "The result is true. Now compare the examples.", previous: "", fontSize: 25, width: 840, height: 110)
        precondition(paired.previous == "The result is true." && paired.text == "Now compare the examples." && paired.height <= 110)
        let waiting = SentenceCaptionLayout.layout(text: "", previous: "The result is true.", fontSize: 25, width: 840, height: 110)
        precondition(waiting.text.isEmpty && waiting.previous == "The result is true.")
        let huge = String(repeating: "When the condition is false, the result must not be accepted; ", count: 20) + "the system keeps all 25 original values."
        for width in [260.0, 660, 1340] {
            for font in [14.0, 25, 90] {
                for lines in [1, 2, 4] {
                    let budget = Double(lines) * CaptionTypesetting.lineHeight(font)
                    let result = SentenceCaptionLayout.layout(text: huge, previous: "An older sentence.", fontSize: font, width: width, height: budget)
                    precondition(!result.text.isEmpty && huge.hasSuffix(result.text) && result.height <= budget, "All sizes must fit without rewriting the words")
                    precondition(result.fontSize <= font && result.fontSize >= min(18, font))
                    let start = huge.index(huge.endIndex, offsetBy: -result.text.count)
                    precondition(start == huge.startIndex || huge[huge.index(before: start)].isWhitespace, "Normal English overflow starts at a word boundary")
                    precondition(result.text.hasSuffix("values."), "Extreme overflow still reaches the end of the sentence")
                }
            }
        }
        for text in [String(repeating: "👩🏽‍🏫", count: 150), String(repeating: "unbroken", count: 100), "Do not remove 3.14, 25%, or p → q."] {
            let result = SentenceCaptionLayout.layout(text: text, previous: "", fontSize: 25, width: 260, height: 70)
            precondition(text.hasSuffix(result.text) && !result.text.isEmpty && result.height <= 70, "Unicode and long unbroken tokens remain safe")
        }
        for language in [CaptionLanguage.chinese, .traditionalChinese] {
            let normalize = language.normalizeScript
            let first = normalize("这个结果是真。"), second = normalize("接着比较三个例子！"), third = normalize("还有问题吗？")
            precondition(SentenceCaptionLayout.sentences(first + second + third, language: language) == [first, second, third], "Chinese punctuation separates sentences without spaces")
            precondition(SentenceCaptionLayout.isComplete("「" + first + "」") && SentenceCaptionLayout.isComplete("“" + third + "”"), "Closing Chinese quotes do not hide final punctuation")
            let numeric = normalize("老师说：「保留3.14和25%。」")
            precondition(SentenceCaptionLayout.sentences(numeric, language: language) == [numeric], "Decimals, percentages and quoted sentences stay intact")
            let chineseSentence = normalize("在这节课上，我们会比较条件为真和条件为假时的三个具体例子，理解计算机如何处理学生输入的信息并显示结果。")
            let fit = SentenceCaptionLayout.layout(text: chineseSentence, previous: "", fontSize: 38, width: 750, height: 95, language: language)
            precondition(fit.text == chineseSentence && fit.fontSize < 38 && fit.height <= 95, "Shrink a complete Chinese sentence before showing a continuation")
            let pair = SentenceCaptionLayout.layout(text: first + second, previous: "", fontSize: 25, width: 840, height: 110, language: language)
            precondition(pair.previous == first && pair.text == second && pair.height <= 110)
            let huge = normalize(String(repeating: "当条件为真时，计算机会处理输入的数据；", count: 30) + "最后保留25%的原始数值。")
            let unpunctuated = normalize(String(repeating: "计算机会根据输入的数据生成相应的结果", count: 30) + "最后保留原始数值。")
            for text in [huge, unpunctuated, String(repeating: "👩🏽‍🏫", count: 150)] {
                for width in [260.0, 660, 1340] {
                    for font in [14.0, 25, 90] {
                        for lines in [1, 2, 4] {
                            let budget = Double(lines) * CaptionTypesetting.lineHeight(font)
                            let result = SentenceCaptionLayout.layout(text: text, previous: first, fontSize: font, width: width, height: budget, language: language)
                            precondition(!result.text.isEmpty && text.hasSuffix(result.text) && result.height <= budget, "Chinese overflow fits and preserves exact text across panel sizes")
                            precondition(result.fontSize <= font && result.fontSize >= min(18, font))
                        }
                    }
                }
            }
            let clause = SentenceCaptionLayout.layout(text: huge, previous: "", fontSize: 25, width: 660, height: 95, language: language)
            let boundary = huge.index(huge.endIndex, offsetBy: -clause.text.count)
            precondition(clause.continued && "，；".contains(huge[huge.index(before: boundary)]), "Chinese overflow prefers a clause boundary without requiring whitespace")
            var reader = SentenceCaptionReading()
            reader.begin(UUID(), language: language, now: 10)
            reader.receive(first, now: 10)
            reader.receive(second, now: 10.1)
            precondition(reader.text == first && reader.nextWakeup == 10.65)
            reader.receive(third, now: 10.2, final: true)
            precondition(reader.text == third && reader.nextWakeup == nil)
            reader.begin(UUID(), language: language, now: 11)
            precondition(reader.previous == third)
            reader.tick(now: 160); precondition(reader.previous == third && reader.nextWakeup == nil)
            reader.receive(first, now: 17)
            reader.begin(UUID(), language: .english, now: 18)
            precondition(reader.previous.isEmpty, "Changing language cannot retain the prior language's context")
        }
        for language in CaptionLanguage.allCases {
            let texts = language == .english ? ["First sentence.", "Second sentence.", "Current sentence.", "Next sentence."]
                : language == .japanese ? ["最初の文です。", "二つ目の文です。", "現在の文です。", "次の文です。"]
                : ["这是第一句。", "这是第二句。", "这是当前句。", "这是下一句。"].map(language.normalizeScript)
            var reader = SentenceCaptionReading()
            for (i, value) in texts.enumerated() {
                reader.begin(UUID(), language: language, now: Double(i))
                reader.receive(value, now: Double(i), final: true)
            }
            precondition(reader.history == Array(texts[1...2]), "Exactly two earlier utterances, in chronological order")
            let layout = SentenceCaptionLayout.layout(text: reader.text, history: reader.history, fontSize: 30, width: 700, height: 220, language: language)
            precondition(layout.text == texts[3] && layout.history == Array(texts[1...2]) && layout.height <= 220)
            let withinCue = SentenceCaptionLayout.layout(text: texts.joined(separator: " "), history: ["obsolete"], fontSize: 30, width: 700, height: 220, language: language)
            precondition(withinCue.history == Array(texts[1...2]), "Multiple sentences in one recognition segment use the same rolling history")
            reader.receive(texts[0], now: 3.1, final: true)
            precondition(reader.history == Array(texts[1...2]), "A revision of the current utterance is not a new history entry")
            let repeated = SentenceCaptionLayout.layout(text: texts[0], history: [texts[0], texts[0]], fontSize: 30, width: 700, height: 220, language: language)
            precondition(repeated.history.count == 2, "Intentional repetitions are not removed")
            let small = SentenceCaptionLayout.layout(text: String(repeating: texts[3], count: 1), history: [String(repeating: texts[0], count: 20), String(repeating: texts[1], count: 20)], fontSize: 38, width: 260, height: SentenceCaptionLayout.minimumHeight(fontSize: 38), language: language)
            precondition(small.history.count == 2 && small.height <= SentenceCaptionLayout.minimumHeight(fontSize: 38), "Small panels reserve both history rows without scrolling")
        }
        print("PASS: four-language current plus two-sentence history, persistent context, revision replacement, repeated phrases, fitting bounds, punctuation, Unicode and bounded partial updates")
    }
}
