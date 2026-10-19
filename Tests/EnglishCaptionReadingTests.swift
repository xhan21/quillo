import AppKit

@main enum EnglishCaptionReadingTests {
    static func main() {
        var reader = EnglishCaptionReading()
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
        reader.tick(now: 16.01); precondition(reader.previous.isEmpty && reader.nextWakeup == nil)
        reader.begin(UUID(), now: 17)
        precondition(reader.previous.isEmpty, "Incomplete fragments are not retained as completed sentences")
        reader.receive("A positive claim", now: 17)
        reader.receive("A corrected claim", now: 17.1)
        reader.flush(now: 17.11)
        precondition(reader.text == "A corrected claim" && reader.nextWakeup == nil)

        let sentences = EnglishCaptionLayout.sentences("Dr. Smith uses 3.14 as an approximation. It is not exact.")
        precondition(sentences.count == 2 && sentences[0].hasPrefix("Dr. Smith") && sentences[0].contains("3.14"), "Sentence parsing preserves common abbreviations and decimals")
        let sentence = "If the condition is true, the computer processes the input and displays the result."
        let fitted = EnglishCaptionLayout.layout(text: sentence, previous: "", fontSize: 38, width: 750, height: 95)
        precondition(fitted.text == sentence && fitted.fontSize < 38 && fitted.fontSize >= 18 && fitted.height <= 95, "Fit the complete conditional sentence before dropping any beginning")
        let paired = EnglishCaptionLayout.layout(text: "The result is true. Now compare the examples.", previous: "", fontSize: 25, width: 840, height: 110)
        precondition(paired.previous == "The result is true." && paired.text == "Now compare the examples." && paired.height <= 110)
        let waiting = EnglishCaptionLayout.layout(text: "", previous: "The result is true.", fontSize: 25, width: 840, height: 110)
        precondition(waiting.text.isEmpty && waiting.previous == "The result is true.")
        let huge = String(repeating: "When the condition is false, the result must not be accepted; ", count: 20) + "the system keeps all 25 original values."
        for width in [260.0, 660, 1340] {
            for font in [14.0, 25, 90] {
                for lines in [1, 2, 4] {
                    let budget = Double(lines) * CaptionTypesetting.lineHeight(font)
                    let result = EnglishCaptionLayout.layout(text: huge, previous: "An older sentence.", fontSize: font, width: width, height: budget)
                    precondition(!result.text.isEmpty && huge.hasSuffix(result.text) && result.height <= budget, "All sizes must fit without rewriting the words")
                    precondition(result.fontSize <= font && result.fontSize >= min(18, font))
                    let start = huge.index(huge.endIndex, offsetBy: -result.text.count)
                    precondition(start == huge.startIndex || huge[huge.index(before: start)].isWhitespace, "Normal English overflow starts at a word boundary")
                    precondition(result.text.hasSuffix("values."), "Extreme overflow still reaches the end of the sentence")
                }
            }
        }
        for text in [String(repeating: "👩🏽‍🏫", count: 150), String(repeating: "unbroken", count: 100), "Do not remove 3.14, 25%, or p → q."] {
            let result = EnglishCaptionLayout.layout(text: text, previous: "", fontSize: 25, width: 260, height: 70)
            precondition(text.hasSuffix(result.text) && !result.text.isEmpty && result.height <= 70, "Unicode and long unbroken tokens remain safe")
        }
        print("PASS: immediate first/final text, bounded partial updates, no backlog, previous-sentence expiry, complete sentence fitting, abbreviations/decimals, clause/word fallback, Unicode and size bounds")
    }
}
