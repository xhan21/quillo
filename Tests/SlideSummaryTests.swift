import AppKit

@MainActor final class ControlledSummarizer {
    struct Call { let request: SlideSummaryRequest; let reply: CheckedContinuation<String, Error> }
    var calls: [Call] = []
    var total = 0
    func generate(_ request: SlideSummaryRequest) async throws -> String {
        total += 1
        return try await withCheckedThrowingContinuation { calls.append(.init(request: request, reply: $0)) }
    }
    func complete(_ text: String) { calls.removeFirst().reply.resume(returning: text) }
}

@main enum SlideSummaryTests {
    @MainActor static func eventually(_ check: () -> Bool) async throws {
        for _ in 0..<300 { if check() { return }; try await Task.sleep(for: .milliseconds(10)) }
        preconditionFailure("Summary did not reach expected state")
    }
    @MainActor static func main() async throws {
        setbuf(stdout, nil)
        _ = NSApplication.shared
        let good = SlideSummaryDocument(overview: "What this slide explains.", points: ["The first key point.", "The second key point."])
        let validated = try good.validated(limit: 200)
        precondition(validated == good.text)
        let compact = try SlideSummaryDocument(overview: "A short main idea.", points: []).validated(limit: 70)
        precondition(compact == "A short main idea.")
        do { _ = try good.validated(limit: 10); preconditionFailure("Must not silently truncate") } catch {}
        do { _ = try SlideSummaryDocument(overview: "", points: ["Point"]).validated(limit: 200); preconditionFailure("Reject empty overview") } catch {}
        do { _ = try SlideSummaryDocument(overview: "命題の定義", points: ["真偽を判断できる文"]).localized(for: .chinese); preconditionFailure("Chinese summary must not retain Japanese sentences") } catch {}
        let simplified = try SlideSummaryDocument(overview: "資訊與電腦", points: ["輸入與處理"]).localized(for: .chinese)
        precondition(simplified.text.contains("信息") || simplified.text.contains("资讯"))
        precondition(simplified.text.contains("电脑"))
        let traditional = try SlideSummaryDocument(overview: "信息与电脑", points: ["输入与处理"]).localized(for: .traditionalChinese)
        precondition(traditional.text.contains("電腦") && traditional.text.contains("輸入"))
        try LocalSlideSummarizer.validateLocalModel(Data(#"{"details":{"format":"gguf"}}"#.utf8))
        try LocalSlideSummarizer.validateLocalModel(Data(#"{"details":{"format":"safetensors","runner":"mlx"}}"#.utf8))
        for bad in [#"{"remote_host":"https://example.com","details":{"format":"gguf"}}"#, #"{"remote_model":"qwen3","details":{"format":"gguf"}}"#, #"{"remote_host":"https://example.com","details":{"format":"safetensors","runner":"mlx"}}"#, #"{"details":{"format":"safetensors"}}"#, #"{"details":{}}"#] {
            do { try LocalSlideSummarizer.validateLocalModel(Data(bad.utf8)); preconditionFailure("Never send a summary to a remote model") } catch {}
        }
        let service = ControlledSummarizer()
        let model = SlideSummaryModel(generate: { try await service.generate($0) })
        model.update(source: "Page A", target: .english, active: false)
        precondition(service.calls.isEmpty, "An inactive source does not invoke the summarizer")
        model.update(source: "Page A", target: .english, active: true)
        try await eventually { service.calls.count == 1 }
        model.update(source: "Page B", target: .english, active: true)
        try await eventually { service.calls.count == 2 }
        service.complete("Old page must not return")
        try await Task.sleep(for: .milliseconds(30))
        precondition(model.text.isEmpty)
        service.complete(good.text)
        try await eventually { model.text == good.text }
        model.update(source: "Page B", target: .english, active: true)
        precondition(service.total == 2, "Do not summarize every frame")
        model.clear()
        model.update(source: "Page B", target: .english, active: true)
        try await eventually { !model.busy }
        precondition(service.total == 2 && model.text == good.text, "Previously visited slide uses memory cache")
        model.update(source: "Page B", target: .english, active: false)
        model.resize(CGSize(width: 200, height: 70))
        precondition(service.calls.isEmpty)
        model.update(source: "Page B", target: .english, active: true)
        try await eventually { service.calls.count == 1 }
        precondition(service.calls[0].request.characterLimit < 200)
        service.complete("Logic.\n\n• True or false.")
        try await eventually { !model.busy }
        precondition(SlidePanelTypesetting.fit(model.text, size: CGSize(width: 200, height: 70), preferredFontSize: 32).pages.count == 1, "A smaller panel requests a shorter summary, not multiple pages")
        model.update(source: "Page C", target: .traditionalChinese, active: true)
        try await eventually { service.calls.count == 1 }
        precondition(service.calls[0].request.target == .traditionalChinese)
        model.clear(); service.complete("Never show after stop")
        try await Task.sleep(for: .milliseconds(30))
        precondition(model.text.isEmpty && !model.busy)
        model.update(source: "Page D", target: .english, active: true)
        try await eventually { service.calls.count == 1 }
        service.calls.removeFirst().reply.resume(throwing: SlideSummaryError.unavailable)
        try await eventually { !model.busy }
        precondition(model.text.isEmpty && model.status.contains("Ollama"), "Show an actionable error instead of pretending to summarize")
        model.clear()
        let dictionary = MaterialGlossary(id: "summary-test", name: "Test", entries: [.init(terms: ["ja": "用語", "en": "term"])])
        model.update(source: "用語を説明します。", target: .english, active: true)
        try await eventually { service.calls.count == 1 }
        precondition(service.calls[0].request.terminology.isEmpty)
        model.setGlossary(dictionary, sourceLanguage: .japanese)
        try await eventually { service.calls.count == 2 }
        precondition(service.calls[1].request.terminology.contains("term"))
        service.complete("Do not show the obsolete glossary result")
        try await Task.sleep(for: .milliseconds(30))
        precondition(model.text.isEmpty)
        service.complete("A term.")
        try await eventually { model.text == "A term." }
        model.setGlossary(nil, sourceLanguage: .japanese)
        try await eventually { service.calls.count == 1 }
        precondition(service.calls[0].request.terminology.isEmpty, "Do not reuse a cache produced with a different glossary")
        service.complete("A normal summary.")
        try await eventually { model.text == "A normal summary." }
        model.clear()
        model.resize(CGSize(width: 438, height: 250))
        let areas: [SlideRegionSource] = [.init(number: 1, text: "First area: input."), .init(number: 2, text: "Second area: output.")]
        model.update(regions: areas, target: .english, active: true)
        try await eventually { service.calls.count == 1 }
        precondition(service.calls[0].request.source == areas[0].text, "A region request must not contain a different region's text")
        service.complete("Input is received.")
        try await eventually { service.calls.count == 1 }
        precondition(service.calls[0].request.source == areas[1].text)
        precondition(model.text.contains("【Area 1】\nInput is received.") && model.text.contains("【Area 2】"), "First result appears with its own number while the second is pending")
        model.update(regions: areas, target: .english, active: false)
        model.update(regions: areas, target: .english, active: true)
        try await eventually { service.calls.count == 2 }
        service.complete("Obsolete second area result.")
        try await Task.sleep(for: .milliseconds(30))
        precondition(!model.text.contains("Obsolete") && model.busy, "Resume a partially completed page and reject its old in-flight result")
        service.complete("Output is displayed.")
        try await eventually { !model.busy }
        precondition(model.text == "【Area 1】\nInput is received.\n\n【Area 2】\nOutput is displayed.")
        precondition(SlidePanelTypesetting.fit(model.text, size: CGSize(width: 438, height: 250), preferredFontSize: 32).pages.count == 1)
        let before = service.total
        model.update(regions: areas, target: .english, active: true)
        precondition(service.total == before, "Unchanged OCR frames do not resummarize areas")
        model.update(regions: [.init(number: 1, text: ""), .init(number: 2, text: "Only area two has text.")], target: .traditionalChinese, active: true)
        try await eventually { service.calls.count == 1 }
        precondition(service.calls[0].request.source == "Only area two has text.")
        service.complete("輸出顯示結果。")
        try await eventually { !model.busy }
        precondition(model.text.contains("【區域1】\n未辨識到文字。") && model.text.contains("【區域2】\n輸出顯示結果。"), "Empty regions retain their selection numbers")
        model.update(regions: [.init(number: 1, text: "New first area"), .init(number: 2, text: "New second area")], target: .english, active: true)
        try await eventually { service.calls.count == 1 }
        service.calls.removeFirst().reply.resume(throwing: SlideSummaryError.failed)
        try await eventually { service.calls.count == 1 }
        service.complete("The second area still works.")
        try await eventually { !model.busy }
        precondition(model.text.contains("【Area 1】\nCould not summarize.") && model.text.contains("【Area 2】\nThe second area still works."), "One region failure cannot hide another region")
        precondition(model.status.contains("範囲1"))
        model.update(regions: [.init(number: 1, text: "Old selection")], target: .english, active: true)
        try await eventually { service.calls.count == 1 }
        model.update(regions: [.init(number: 1, text: ""), .init(number: 2, text: "New selection")], target: .english, active: true)
        try await eventually { service.calls.count == 2 }
        service.complete("Do not mislabel this obsolete result.")
        try await Task.sleep(for: .milliseconds(30))
        precondition(!model.text.contains("obsolete"))
        service.complete("A new selection.")
        try await eventually { !model.busy }
        precondition(model.text.contains("【Area 2】\nA new selection."))
        model.clear()
        model.resize(CGSize(width: 220, height: 70))
        model.update(regions: (1...3).map { .init(number: $0, text: "") }, target: .english, active: true)
        try await eventually { !model.busy }
        precondition(model.text.isEmpty && model.status.contains("大きく"))
        model.resize(CGSize(width: 438, height: 300))
        try await eventually { !model.busy }
        precondition(model.text.contains("【Area 3】\nNo text found."), "Enlarging a panel recovers from insufficient space without requiring another source selection")
        model.clear()
        print("PASS: independent numbered regions, empty region numbering, progressive output, per-region errors/cache and stale selection rejection")
        print("PASS: local-only model validation, no truncation, stale result exclusion, stop cancellation, no per-frame requests, page cache, resize compaction, Traditional Chinese target, recoverable errors")

        if CommandLine.arguments.contains("--live") {
            let local = LocalSlideSummarizer()
            let source = "命題と真理値。命題とは、真か偽かを客観的に判断できる文のこと。『2は偶数である』は真の命題。『3は偶数である』は偽の命題。疑問文や命令文は命題ではない。『xは偶数である』はxの値を定めるまでは真理値が確定しない。命題をpやqで表し、真をT、偽をFで表す。"
            for language in CaptionLanguage.allCases {
                let start = ContinuousClock.now
                print("LIVE starting \(language.rawValue)")
                // Verify the same fit-and-resummarize path as the app. A character
                // budget alone cannot promise a particular measured text height.
                let display = SlideSummaryModel(generate: { try await local.summarize($0) })
                let size = CGSize(width: 348, height: 210)
                display.resize(size)
                display.update(source: source, target: language, active: true)
                for _ in 0..<1000 {
                    if !display.busy { break }
                    try await Task.sleep(for: .milliseconds(100))
                }
                guard !display.busy, !display.text.isEmpty else { print("LIVE FAILED \(language.rawValue): \(display.status)"); exit(1) }
                let result = display.text
                print("LIVE \(language.rawValue) [\(start.duration(to: .now))]:\n\(result)")
                precondition(SlidePanelTypesetting.fit(result, size: size, preferredFontSize: 20).pages.count == 1)
                display.clear()
            }
            let compactSource = "情報の流れを見てみよう。入力した情報を、コンピュータが処理します。処理した結果は、画面や音で伝えられます。"
            let result = try await local.summarize(.init(source: compactSource, target: .english, characterLimit: 120))
            print("LIVE compact:\n\(result)")
            precondition(result.count <= 120)
            precondition(SlidePanelTypesetting.fit(result, size: CGSize(width: 348, height: 108), preferredFontSize: 16).pages.count == 1)
        }
    }
}
