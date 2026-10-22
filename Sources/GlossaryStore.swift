import AppKit
import Combine
import UniformTypeIdentifiers

@MainActor
final class GlossaryStore: ObservableObject {
    @Published private(set) var dictionaries: [MaterialGlossary] = []
    @Published private(set) var selectedID: String
    @Published private(set) var message = ""
    var onChange: (() -> Void)?
    private let directory: URL
    private let defaults: UserDefaults
    var selected: MaterialGlossary? { dictionaries.first { $0.id == selectedID } }
    let common = CommonVocabulary.glossary
    var effective: MaterialGlossary { .combining(common: common, course: selected) }
    var translationGlossary: MaterialGlossary { .combining(common: CommonVocabulary.translationGlossary, course: selected) }
    func correctionTerms(in source: String, language: CaptionLanguage, previousSource: String) -> String {
        let combined = effective
        let matched = combined.summaryTerms(in: source, language: language, target: language)
        // Explicit course mappings take precedence. Only the reported standalone
        // confusion gets this fallback; do not bias longer text or colour context.
        guard matched.isEmpty, language == .japanese,
              previousSource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return matched }
        let word = source.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "。．.!！?？")))
        guard let preferred = CommonVocabulary.isolatedInputSpellings[word],
              combined.entries.contains(where: { $0.term(language) == preferred }),
              let data = try? JSONSerialization.data(withJSONObject: [["source": word, "preferred": preferred]], options: [.sortedKeys]) else { return matched }
        return String(decoding: data, as: UTF8.self)
    }
    func recognitionPhrases(_ language: CaptionLanguage) -> [String] {
        let combined = effective
        let course = selected?.recognitionPhrases(language) ?? []
        let courseCount = selected?.entries.count ?? 0
        let commonEntries = Array(combined.entries.dropFirst(selected == nil ? 0 : courseCount))
        let commonPhrases = commonEntries.compactMap { $0.term(language) }
            + (language == .japanese ? CommonVocabulary.conversation : [])
            + commonEntries.flatMap { $0.aliases[language.rawValue] ?? [] }
        // Share Apple's 100 hints: reserve up to 40 for common words so a full
        // course dictionary cannot disable them; unused capacity goes to either.
        let shared = Array(commonPhrases.prefix(40))
        let priority = Array(course.prefix(100 - shared.count)) + shared + course + commonPhrases
        var seen = Set<String>()
        return Array(priority.filter { seen.insert($0.lowercased()).inserted }.prefix(100))
    }
    init(directory: URL? = nil, defaults: UserDefaults = .standard) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Quillo/Glossaries", isDirectory: true)
        self.defaults = defaults
        selectedID = defaults.string(forKey: "selectedMaterialGlossary") ?? ""
        load()
    }
    private func load() {
        var failed = 0
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        dictionaries = files.filter { $0.pathExtension == "json" }.compactMap { url in
            do {
                guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 262_144 else { throw GlossaryError.invalidFile }
                return try MaterialGlossary.decode(Data(contentsOf: url))
            } catch { failed += 1; return nil }
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if failed > 0 { message = "読み込めない辞書が\(failed)件あります。元のファイルは残っています。" }
        if !selectedID.isEmpty && selected == nil { selectedID = "" }
    }
    func select(_ id: String) {
        let id = dictionaries.contains { $0.id == id } ? id : ""
        guard selectedID != id else { return }
        selectedID = id; defaults.set(id, forKey: "selectedMaterialGlossary"); onChange?()
    }
    func importFile(_ url: URL) throws {
        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 262_144 else { throw GlossaryError.invalidFile }
        let glossary = try MaterialGlossary.decode(Data(contentsOf: url))
        let data = try JSONEncoder().encode(glossary)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(glossary.id + ".json"), options: .atomic)
        load(); selectedID = glossary.id; defaults.set(selectedID, forKey: "selectedMaterialGlossary")
        message = "「\(glossary.name)」の\(glossary.entries.count)語を読み込みました。"
        onChange?()
    }
    func chooseImport() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        panel.message = "資料用の辞書ファイルを選んでください。同じIDの辞書は更新されます。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try importFile(url) } catch { message = (error as? GlossaryError)?.localizedDescription ?? "辞書を保存できませんでした。ファイルを確認してください。" }
    }
}
