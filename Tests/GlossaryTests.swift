import AppKit

@MainActor final class GlossaryTranslatorStub {
    var calls: [(String, CheckedContinuation<String, Error>)] = []
    func translate(_ text: String) async throws -> String {
        try await withCheckedThrowingContinuation { calls.append((text, $0)) }
    }
    func complete(_ text: String) { calls.removeFirst().1.resume(returning: text) }
}

@main enum GlossaryTests {
    static let basic = MaterialGlossary(id: "test", name: "Test vocabulary", entries: [
        .init(terms: ["ja": "命題", "en": "proposition", "zh-Hans": "命题", "zh-Hant": "命題"]),
        .init(terms: ["ja": "複合命題", "en": "compound proposition", "zh-Hans": "复合命题", "zh-Hant": "複合命題"]),
        .init(terms: ["ja": "論理和", "en": "disjunction", "zh-Hans": "析取", "zh-Hant": "析取"], aliases: ["ja": ["選言"]]),
        .init(terms: ["ja": "集合", "en": "set", "zh-Hans": "集合", "zh-Hant": "集合"])
    ])
    @MainActor static func eventually(_ check: () -> Bool) async throws {
        for _ in 0..<300 { if check() { return }; try await Task.sleep(for: .milliseconds(10)) }
        preconditionFailure("Glossary operation timed out")
    }
    @MainActor static func main() async throws {
        setbuf(stdout, nil); _ = NSApplication.shared
        let glossary = try MaterialGlossary.decode(JSONEncoder().encode(basic))
        precondition(glossary == basic)
        let source = "複合命題と命題、選言について説明します。"
        let protected = GlossaryTranslation(source: source, language: .japanese, target: .english, glossary: glossary)
        precondition(protected.input == "QZTERM000QZとQZTERM001QZ、QZTERM002QZについて説明します。")
        precondition(protected.restore("We explain QZTERM000QZ, QZTERM001QZ, and QZTERM002QZ.") == "We explain compound proposition, proposition, and disjunction.")
        precondition(protected.restore("QZTERM000QZ and QZTERM002QZ") == nil)
        precondition(protected.restore("QZTERM000QZ QZTERM001QZ QZTERM002QZ QZTERM002QZ") == nil)
        precondition(protected.restore("QZ TERM 000 QZ QZ TERM 001 QZ QZ TERM 002 QZ") == nil)
        let collision = GlossaryTranslation(source: "QZTERM 命題", language: .japanese, target: .english, glossary: glossary)
        precondition(collision.input == "QZTERM QZTERMX000QZ")
        precondition(collision.restore("QZTERM QZTERMX000QZ") == "QZTERM proposition")
        let english = glossary.matches(in: "Reset the dataset. A set and a SET.", language: .english, target: .japanese)
        precondition(english.count == 2, "Never replace set inside reset or dataset")
        let exact = GlossaryTranslation(source: "選言", language: .japanese, target: .traditionalChinese, glossary: glossary)
        let term = try await exact.translate { _ in preconditionFailure("Exact terms need no extra translation") }
        precondition(term == "析取")
        var requests: [String] = []
        let fallback = try await protected.translate { text in requests.append(text); return requests.count == 1 ? "broken marker" : "Safe normal translation" }
        precondition(fallback == "Safe normal translation" && requests == [protected.input, source])
        let none = GlossaryTranslation(source: "教材を開きます。", language: .japanese, target: .english, glossary: glossary)
        precondition(!none.hasTerms && none.input == none.source)
        let same = GlossaryTranslation(source: source, language: .japanese, target: .japanese, glossary: glossary)
        precondition(!same.hasTerms)
        precondition(glossary.recognitionPhrases(.japanese).contains("選言"))
        let summaryTerms = glossary.summaryTerms(in: "複合命題と選言", language: .japanese, target: .traditionalChinese)
        precondition(summaryTerms.contains("複合命題") && summaryTerms.contains("析取") && !summaryTerms.contains("集合"))
        let traditionalTerms = basic.summaryTerms(in: "論理和と命題", language: .japanese, target: .traditionalChinese)
        precondition(MaterialGlossary.normalizeSummary("論理和：任一命題為真則結果為真", terminology: traditionalTerms) == "析取：任一命題為真則結果為真")
        precondition(MaterialGlossary.normalizeSummary("析取與命題", terminology: traditionalTerms) == "析取與命題")
        precondition(MaterialGlossary.normalizeSummary("論理和：任一命題為真", terminology: "") == "論理和：任一命題為真")
        precondition(MaterialGlossary.normalizeSummary("term and terminology", terminology: #"[{"source":"term","preferred":"terminology"}]"#) == "terminology and terminology")
        for invalid in [MaterialGlossary(id: "../escape", name: "Bad", entries: basic.entries),
                        MaterialGlossary(id: "bad", name: "Bad", entries: [basic.entries[0], .init(terms: ["ja": "命題", "en": "other"])])] {
            do { _ = try MaterialGlossary.decode(JSONEncoder().encode(invalid)); preconditionFailure("Invalid dictionary accepted") } catch {}
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("quillo-glossary-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "quillo-glossary-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        // Isolated preference domain and dictionary directory; never read personal data.
        defer { defaults.removePersistentDomain(forName: suite) }
        let file = root.appendingPathComponent("import.json"), directory = root.appendingPathComponent("saved")
        try JSONEncoder().encode(basic).write(to: file)
        let store = GlossaryStore(directory: directory, defaults: defaults)
        let common = try MaterialGlossary.decode(JSONEncoder().encode(CommonVocabulary.glossary))
        precondition(common.entries.count == 25 && CommonVocabulary.conversation.count == 12)
        precondition(store.selected == nil && store.effective == common)
        // Reproduce the owner's exact ASR result: the original exact-match path
        // provides no terms, so the short-input guard rejects the desired repair.
        precondition(store.effective.summaryTerms(in: "怖い色", language: .japanese, target: .japanese).isEmpty)
        precondition((try? LocalCaptionCorrector.validate("声色", for: .init(source: "怖い色", language: .japanese))) == nil)
        for raw in ["怖い色", "怖い色。", " 怖い色！ "] {
            let terms = store.correctionTerms(in: raw, language: .japanese, previousSource: "")
            precondition(terms.contains("声色"))
            precondition((try? LocalCaptionCorrector.validate("声色", for: .init(source: raw, language: .japanese, terminology: terms))) == "声色")
            precondition((try? LocalCaptionCorrector.validate("声色です。", for: .init(source: raw, language: .japanese, terminology: terms))) == nil,
                         "Do not accept an invented copula while repairing an isolated word")
        }
        for raw in ["怖い色を使います。", "怖い色とは何ですか。", "赤は怖い色です。", "怖い", "色", "丈夫"] {
            precondition(store.correctionTerms(in: raw, language: .japanese, previousSource: "").isEmpty)
            let candidate = raw.replacingOccurrences(of: "怖い色", with: "声色")
            if candidate != raw {
                precondition((try? LocalCaptionCorrector.validate(candidate, for: .init(source: raw, language: .japanese))) == nil)
            }
        }
        precondition(store.correctionTerms(in: "怖い色", language: .japanese, previousSource: "絵に使う色を選びます。").isEmpty)
        precondition(store.correctionTerms(in: "怖い色", language: .english, previousSource: "").isEmpty)
        precondition(!GlossaryTranslation(source: "怖い色", language: .japanese, target: .english, glossary: store.translationGlossary).hasTerms)
        for phrase in ["声色", "こわいろ", "ローカルLLM", "大丈夫です", "なるほど"] {
            precondition(store.recognitionPhrases(.japanese).contains(phrase))
        }
        precondition(store.effective.matches(in: "丈夫な素材", language: .japanese, target: .english).isEmpty,
                     "Never register a valid ordinary word as a mistaken alias")
        precondition(!GlossaryTranslation(source: "よろしくお願いします", language: .japanese, target: .english,
                                         glossary: store.translationGlossary).hasTerms)
        try store.importFile(file)
        precondition(store.selected == basic)
        precondition(store.effective.entries.contains(common.entries[0]) && store.effective.entries.contains(basic.entries[0]))
        let both = GlossaryTranslation(source: "こわいろと命題", language: .japanese, target: .english, glossary: store.translationGlossary)
        precondition(both.restore("QZTERM000QZ and QZTERM001QZ") == "tone of voice and proposition")
        let hints = store.effective.summaryTerms(in: "こわいろとローカルエルエルエム", language: .japanese, target: .japanese)
        let correction = CaptionCorrectionRequest(source: "こわいろとローカルエルエルエム", language: .japanese, terminology: hints)
        precondition((try? LocalCaptionCorrector.validate("声色とローカルLLM", for: correction)) == "声色とローカルLLM")
        precondition((try? LocalCaptionCorrector.validate("声色とローカル LLM", for: correction)) == "声色とローカル LLM")
        precondition((try? LocalCaptionCorrector.validate("声色とクラウドLLM", for: correction)) == nil)
        let colourCourse = MaterialGlossary(id: "colour-course", name: "Colour", entries: [
            .init(terms: ["ja": "怖い色", "en": "scary colour"])])
        try JSONEncoder().encode(colourCourse).write(to: file); try store.importFile(file)
        let colourTerms = store.correctionTerms(in: "怖い色", language: .japanese, previousSource: "")
        precondition(!colourTerms.contains("声色") && colourTerms.contains("怖い色"))
        precondition((try? LocalCaptionCorrector.validate("声色", for: .init(source: "怖い色", language: .japanese, terminology: colourTerms))) == nil)
        store.select("test")
        let preferred = MaterialGlossary(id: "voice-course", name: "Voice", entries: [
            .init(terms: ["ja": "声色", "en": "vocal expression"], aliases: ["ja": ["こわいろ"]])])
        let merged = MaterialGlossary.combining(common: common, course: preferred)
        precondition(merged.matches(in: "こわいろ", language: .japanese, target: .english).first?.entry.term(.english) == "vocal expression")
        precondition(!merged.entries.contains(common.entries[0]) && common.entries[0].term(.english) == "tone of voice")
        // Full course dictionaries cannot push every shared hint out of Apple's cap.
        let full = MaterialGlossary(id: "full", name: "Full", entries: (0..<100).map {
            .init(terms: ["ja": "授業用語\($0)", "en": "course term \($0)"])
        })
        try JSONEncoder().encode(full).write(to: file); try store.importFile(file)
        let phrases = store.recognitionPhrases(.japanese)
        precondition(phrases.count == 100 && Set(phrases).count == 100)
        precondition(phrases.contains("授業用語0") && phrases.contains("声色") && phrases.contains("こわいろ") && phrases.contains("大丈夫です"))
        // A combined library must retain words beyond the speech hint budget.
        let library = MaterialGlossary(id: "library", name: "Combined test library", entries: (0..<500).map {
            .init(terms: ["ja": "試験用語\($0)", "en": "test term \($0)", "zh-Hans": "测试术语\($0)", "zh-Hant": "測試術語\($0)"],
                  aliases: ["ja": ["てすとようご\($0)"]])
        })
        try JSONEncoder().encode(library).write(to: file); try store.importFile(file)
        let reloadedLibrary = GlossaryStore(directory: directory, defaults: defaults)
        precondition(reloadedLibrary.selected == library, "All 500 terms and the selection survive reload")
        precondition(reloadedLibrary.recognitionPhrases(.japanese).count == 100)
        precondition(reloadedLibrary.recognitionPhrases(.japanese).contains("大丈夫です"))
        for language in [CaptionLanguage.english, .chinese, .traditionalChinese] {
            let last = GlossaryTranslation(source: "てすとようご499", language: .japanese, target: language,
                                          glossary: reloadedLibrary.translationGlossary)
            precondition(last.exactTerm == library.entries.last?.term(language))
            precondition(reloadedLibrary.effective.summaryTerms(in: "試験用語499", language: .japanese, target: language)
                .contains(library.entries.last!.term(language)!))
        }
        precondition(reloadedLibrary.correctionTerms(in: "てすとようご499", language: .japanese, previousSource: "")
            .contains("試験用語499"))
        let tooLarge = MaterialGlossary(id: "too-large", name: "Too large", entries: library.entries + basic.entries.prefix(1))
        try JSONEncoder().encode(tooLarge).write(to: file)
        do { try store.importFile(file); preconditionFailure("501 entries accepted") } catch GlossaryError.invalidFile {}
        precondition(store.selected == library, "A rejected import must preserve the selected library")
        store.select("test")
        let loaded = GlossaryStore(directory: directory, defaults: defaults)
        precondition(loaded.selected == basic, "Selected dictionary survives restart")
        loaded.select(""); precondition(loaded.selected == nil && loaded.effective == common)
        let model = AppModel(glossary: store)
        model.clearCaption(); model.isListening = true
        let id = UUID()
        model.speech.onText?(.init(segmentID: id, text: "命題を説明します。"), false)
        let translator = GlossaryTranslatorStub()
        let worker = Task { await model.runTranslationWorker(prepare: {}, translate: { try await translator.translate($0) }) }
        try await eventually { translator.calls.count == 1 }
        precondition(translator.calls[0].0 == "QZTERM000QZを説明します。")
        store.select("")
        precondition(model.isListening && model.sourceText == "命題を説明します。" && model.translationReady)
        translator.complete("Explain QZTERM000QZ.")
        try await eventually { translator.calls.count == 1 }
        precondition(model.translatedText.isEmpty && translator.calls[0].0 == "命題を説明します。", "Do not display results from the previous dictionary")
        translator.complete("Explain a proposition.")
        try await eventually { model.translatedText == "Explain a proposition." }
        store.select("test")
        try await eventually { translator.calls.count == 1 }
        translator.complete("Explain QZTERM000QZ.")
        try await eventually { model.translatedText == "Explain proposition." }
        precondition(model.speech.contextualPhrases.contains("命題"))
        model.shutdown(); worker.cancel(); await worker.value
        print("PASS: always-on common vocabulary, course precedence, shared recognition budget, reading-to-term correction, four-language matching, storage/restart, stale caption exclusion and session preservation")
        if CommandLine.arguments.contains("--live-homophone") {
            let service = LocalCaptionCorrector()
            await service.warmUp()
            for (raw, previous, expected) in [("怖い色", "", "声色"), ("怖い色。", "", "声色。"),
                ("怖い色を使います。", "", "怖い色を使います。"), ("怖い色", "絵に使う色を選びます。", "怖い色")] {
                let terms = store.correctionTerms(in: raw, language: .japanese, previousSource: previous)
                let input = CaptionCorrectionRequest(source: raw, language: .japanese, previousSource: previous, terminology: terms)
                let start = Date()
                do {
                    let result = try await service.correct(input)
                    print("LIVE HOMOPHONE: \(raw) -> \(result) (\(Date().timeIntervalSince(start)) seconds; previous: \(previous))")
                    precondition(result == expected)
                } catch CaptionCorrectionError.invalidResult where expected == raw {
                    // The app retains the original on rejected candidates. Count
                    // that separately from the model itself leaving it unchanged.
                    print("LIVE HOMOPHONE GUARDED: retained \(raw); candidate rejected (previous: \(previous))")
                }
            }
        }
        if CommandLine.arguments.contains("--live") {
            let correctionService = LocalCaptionCorrector()
            for text in ["こわいろを変えて説明します。", "ローカルエルエルエムを使います。"] {
                let terms = store.effective.summaryTerms(in: text, language: .japanese, target: .japanese)
                let start = Date()
                do {
                    let result = try await correctionService.correct(.init(source: text, language: .japanese, terminology: terms))
                    print("LIVE COMMON INPUT: \(text) -> \(result) (\(Date().timeIntervalSince(start)) seconds)")
                } catch { print("LIVE COMMON INPUT: \(text) -> unchanged (\(error))") }
            }
            let service = LocalSlideSummarizer()
            let source = "論理和は、どちらか一方または両方の命題が真ならば真となる。複合命題は複数の命題を組み合わせたもの。"
            for language in [CaptionLanguage.english, .traditionalChinese] {
                let terms = basic.summaryTerms(in: source, language: .japanese, target: language)
                let result = try await service.summarize(.init(source: source, target: language, characterLimit: language == .english ? 420 : 220, terminology: terms))
                print("LIVE \(language.rawValue): \(result)")
                precondition(result.localizedCaseInsensitiveContains(basic.entries[2].term(language)!))
            }
        }
    }
}
