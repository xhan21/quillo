import AppKit

@main enum SlidePanelTests {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let text = (1...16).map { "\($0). Every paragraph from the selected slide stays complete in the translation panel. 日本語と繁體字資訊も確認します。👩🏽‍🏫" }.joined(separator: "\n\n")
        for width in [180.0, 380, 700] { for height in [100.0, 350, 600] { for preferred in [12.0, 22, 32] {
            let result = SlidePanelTypesetting.fit(text, size: CGSize(width: width, height: height), preferredFontSize: preferred)
            precondition(result.pages.map(\.text).joined() == text, "Never omit any text, newline, or Unicode grapheme")
            precondition(result.fontSize >= 12 && result.fontSize <= preferred)
            for page in result.pages {
                precondition(SlidePanelTypesetting.measuredHeight(page.text, fontSize: result.fontSize, width: width) <= height - 4, "Every page must fit")
            }
            if result.pages.count > 1 { precondition(result.fontSize == 12) }
        } } }
        let short = SlidePanelTypesetting.fit("A short paragraph.", size: CGSize(width: 400, height: 300), preferredFontSize: 28)
        precondition(short.pages.count == 1 && short.fontSize == 28)
        let fitting = SlidePanelTypesetting.fit(String(repeating: "A complete paragraph. ", count: 35), size: CGSize(width: 500, height: 420), preferredFontSize: 32)
        precondition(fitting.pages.count == 1 && fitting.fontSize < 32 && fitting.fontSize >= 12, "Shrink before paging")
        let a = SlideTextBlock(id: 0, text: "Alpha", rect: .zero), b = SlideTextBlock(id: 1, text: "Beta", rect: .zero)
        precondition(SlidePanelTypesetting.pageKey(document: "Deck", blocks: [a,b]) == SlidePanelTypesetting.pageKey(document: "Deck", blocks: [b,a]), "Reading-order keys ignore reorder")
        precondition(SlidePanelTypesetting.pageKey(document: "Deck", blocks: [a]) != SlidePanelTypesetting.pageKey(document: "Other", blocks: [a]))
        let parts = SlidePanelTypesetting.listParts("12. 日本語の項目")
        precondition(parts.marker == "12. " && parts.body == "日本語の項目")
        precondition(SlidePanelTypesetting.listParts("-3 is negative").marker.isEmpty)
        let presenter = SlidePanelPresentation()
        presenter.resize(CGSize(width: 120, height: 65))
        presenter.update(text: text, revision: 1, preferred: 22)
        presenter.step(1)
        let anchor = presenter.layout.pages[presenter.page].start
        presenter.resize(CGSize(width: 150, height: 85))
        precondition(presenter.layout.pages[presenter.page].start <= anchor && presenter.layout.pages[presenter.page].end > anchor, "Resize preserves the reading location")
        presenter.update(text: "New slide", revision: 2, preferred: 22)
        precondition(presenter.page == 0 && presenter.currentText == "New slide", "New slide replaces old text immediately")
        presenter.resize(CGSize(width: 70, height: 45))
        presenter.update(text: text, revision: 3, preferred: 12)
        presenter.setActive(true)
        let deadline = ContinuousClock.now + .seconds(35)
        while presenter.page == 0 && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        precondition(presenter.page > 0, "Overflow advances without scrolling")
        presenter.setActive(false)
        presenter.update(text: "", revision: 4, preferred: 16)
        precondition(presenter.currentText.isEmpty && presenter.layout.pages.isEmpty, "Clear cancels old pages")
        print("PASS: full-text auto fit, 12 pt lower bound, Unicode-safe overflow, page-specific ordering key, list markers, resize anchor, source-page replacement, automatic advance and clear")
    }
}
