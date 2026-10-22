import Foundation

struct GlossaryEntry: Codable, Equatable {
    let terms: [String: String]
    var aliases: [String: [String]] = [:]
    init(terms: [String: String], aliases: [String: [String]] = [:]) { self.terms = terms; self.aliases = aliases }
    private enum CodingKeys: String, CodingKey { case terms, aliases }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        terms = try values.decode([String: String].self, forKey: .terms)
        aliases = try values.decodeIfPresent([String: [String]].self, forKey: .aliases) ?? [:]
    }
    func term(_ language: CaptionLanguage) -> String? { terms[language.rawValue] }
    func phrases(_ language: CaptionLanguage) -> [String] {
        ([term(language)].compactMap { $0 } + (aliases[language.rawValue] ?? []))
    }
}

struct MaterialGlossary: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let entries: [GlossaryEntry]

    // The chosen course wins on any shared canonical spelling or alias, in any
    // language. Drop the conflicting common entry as a whole to avoid inconsistent
    // forward/reverse translations. Neither source dictionary is mutated.
    static func combining(common: MaterialGlossary, course: MaterialGlossary?) -> MaterialGlossary {
        guard let course else { return common }
        func keys(_ entry: GlossaryEntry) -> Set<String> {
            Set(CaptionLanguage.allCases.flatMap { language in
                entry.phrases(language).map { language.rawValue + "|" + $0.lowercased() }
            })
        }
        let courseKeys = course.entries.reduce(into: Set<String>()) { $0.formUnion(keys($1)) }
        let shared = common.entries.filter { keys($0).isDisjoint(with: courseKeys) }
        return MaterialGlossary(id: "quillo-effective", name: course.name + " ＋ 共通辞書", entries: course.entries + shared)
    }

    static func decode(_ data: Data) throws -> MaterialGlossary {
        guard data.count <= 262_144 else { throw GlossaryError.invalidFile }
        let value = try JSONDecoder().decode(Self.self, from: data)
        let languages = Set(CaptionLanguage.allCases.map(\.rawValue))
        func validPhrase(_ phrase: String) -> Bool {
            !captionText(phrase).isEmpty && phrase == captionText(phrase) && phrase.count <= 80
                && !phrase.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        }
        guard value.id.range(of: "^[A-Za-z0-9_-]{1,80}$", options: .regularExpression) != nil,
              validPhrase(value.name), !value.entries.isEmpty, value.entries.count <= 100 else { throw GlossaryError.invalidFile }
        var seen: [String: Int] = [:]
        for (index, entry) in value.entries.enumerated() {
            guard entry.terms.count >= 2, Set(entry.terms.keys).isSubset(of: languages),
                  Set(entry.aliases.keys).isSubset(of: Set(entry.terms.keys)),
                  entry.terms.values.allSatisfy(validPhrase),
                  entry.aliases.values.allSatisfy({ $0.count <= 8 && $0.allSatisfy(validPhrase) }) else { throw GlossaryError.invalidFile }
            for language in CaptionLanguage.allCases {
                for phrase in entry.phrases(language) {
                    let key = language.rawValue + "|" + phrase.lowercased()
                    if let previous = seen[key], previous != index { throw GlossaryError.ambiguousTerm }
                    seen[key] = index
                }
            }
        }
        return value
    }

    func recognitionPhrases(_ language: CaptionLanguage) -> [String] {
        // Apple recommends at most 100 short contextual phrases. Prefer canonical
        // terms before aliases so a large dictionary does not drop whole concepts.
        var seen = Set<String>()
        return Array((entries.compactMap { $0.term(language) } + entries.flatMap { $0.aliases[language.rawValue] ?? [] })
            .filter { seen.insert($0).inserted }.prefix(100))
    }

    struct Match { let range: NSRange; let entry: GlossaryEntry }
    func matches(in source: String, language: CaptionLanguage, target: CaptionLanguage) -> [Match] {
        let text = source as NSString
        var candidates: [Match] = []
        for entry in entries where entry.term(target) != nil {
            for phrase in entry.phrases(language) {
                // Single characters (真, 裏, p, etc.) are too ambiguous in prose.
                guard phrase.count >= 2 else { continue }
                let escaped = NSRegularExpression.escapedPattern(for: phrase)
                let asciiStart = phrase.first?.isASCII == true && phrase.first?.isLetter == true
                let asciiEnd = phrase.last?.isASCII == true && phrase.last?.isLetter == true
                let pattern = (asciiStart ? "(?<![A-Za-z0-9_])" : "") + escaped + (asciiEnd ? "(?![A-Za-z0-9_])" : "")
                guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
                candidates += regex.matches(in: source, range: NSRange(location: 0, length: text.length)).map { Match(range: $0.range, entry: entry) }
            }
        }
        // At a shared start, prefer the whole compound over its shorter suffix.
        candidates.sort { $0.range.location == $1.range.location ? $0.range.length > $1.range.length : $0.range.location < $1.range.location }
        var end = 0
        return candidates.filter { match in
            guard match.range.location >= end else { return false }
            end = NSMaxRange(match.range); return true
        }
    }

    func summaryTerms(in source: String, language: CaptionLanguage, target: CaptionLanguage) -> String {
        var seen = Set<String>()
        let pairs = matches(in: source, language: language, target: target).compactMap { match -> [String: String]? in
            let original = (source as NSString).substring(with: match.range)
            guard let preferred = match.entry.term(target), seen.insert(original).inserted else { return nil }
            return ["source": original, "preferred": preferred]
        }
        guard !pairs.isEmpty, let data = try? JSONSerialization.data(withJSONObject: pairs, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else { return "" }
        return json
    }

    // Some local models retain CJK source terms despite the requested language.
    // Correct only source spellings from the input-scoped vocabulary; leave
    // existing preferred spellings and all other prose alone.
    static func normalizeSummary(_ text: String, terminology: String) -> String {
        guard let data = terminology.data(using: .utf8), let pairs = try? JSONDecoder().decode([[String: String]].self, from: data) else { return text }
        let length = (text as NSString).length
        func ranges(_ phrase: String) -> [NSRange] {
            guard phrase.count >= 2 else { return [] }
            let left = phrase.first?.isASCII == true && phrase.first?.isLetter == true ? "(?<![A-Za-z0-9_])" : ""
            let right = phrase.last?.isASCII == true && phrase.last?.isLetter == true ? "(?![A-Za-z0-9_])" : ""
            let regex = try? NSRegularExpression(pattern: left + NSRegularExpression.escapedPattern(for: phrase) + right, options: .caseInsensitive)
            return regex?.matches(in: text, range: NSRange(location: 0, length: length)).map(\.range) ?? []
        }
        let applicable = pairs.filter { $0["source"] != nil && $0["preferred"] != nil && $0["source"] != $0["preferred"] }
        let protected = applicable.flatMap { ranges($0["preferred"]!) }
        var matches: [(NSRange, String)] = applicable.flatMap { pair in
            ranges(pair["source"]!).filter { range in !protected.contains { NSIntersectionRange($0, range).length > 0 } }.map { ($0, pair["preferred"]!) }
        }
        matches.sort { $0.0.location == $1.0.location ? $0.0.length > $1.0.length : $0.0.location < $1.0.location }
        let original = text as NSString
        var output = "", end = 0
        for (range, term) in matches where range.location >= end {
            output += original.substring(with: NSRange(location: end, length: range.location - end)) + term
            end = NSMaxRange(range)
        }
        return output + original.substring(from: end)
    }
}

enum GlossaryError: LocalizedError {
    case invalidFile, ambiguousTerm
    var errorDescription: String? {
        switch self {
        case .invalidFile: return "辞書を読み込めませんでした。辞書名・用語・言語を確認してください（100語、256KBまで）。"
        case .ambiguousTerm: return "同じ言葉に異なる訳語が登録されています。辞書を確認してください。"
        }
    }
}

// Apple Translation has no custom glossary parameter on macOS 15. Protect only
// matched terminology, translate the sentence once, then restore the preferred
// terms. Reject altered/missing/duplicated markers and retry the original text.
// Never send instructions as if they were part of the speaker's sentence.
struct GlossaryTranslation {
    let source: String
    let input: String
    private let prefix: String
    private let replacements: [(String, String)]
    let exactTerm: String?
    var hasTerms: Bool { !replacements.isEmpty }

    init(source: String, language: CaptionLanguage, target: CaptionLanguage, glossary: MaterialGlossary?) {
        self.source = source
        var prefix = "QZTERM"
        while source.range(of: prefix, options: .caseInsensitive) != nil { prefix += "X" }
        self.prefix = prefix
        let matches = glossary?.matches(in: source, language: language, target: target) ?? []
        guard language != target, !matches.isEmpty, matches.count <= 512 else {
            input = source; replacements = []; exactTerm = nil; return
        }
        let original = source as NSString
        exactTerm = matches.count == 1 && matches[0].range == NSRange(location: 0, length: original.length) ? matches[0].entry.term(target) : nil
        var output = "", end = 0, values: [(String, String)] = []
        for (index, match) in matches.enumerated() {
            let marker = prefix + String(format: "%03d", index) + "QZ"
            output += original.substring(with: NSRange(location: end, length: match.range.location - end)) + marker
            values.append((marker, match.entry.term(target)!)); end = NSMaxRange(match.range)
        }
        output += original.substring(from: end)
        input = output; replacements = values
    }

    func restore(_ translated: String) -> String? {
        guard hasTerms else { return translated }
        var output = translated
        for (marker, term) in replacements {
            let regex = try! NSRegularExpression(pattern: NSRegularExpression.escapedPattern(for: marker), options: .caseInsensitive)
            let matches = regex.matches(in: output, range: NSRange(output.startIndex..., in: output))
            guard matches.count == 1, let range = Range(matches[0].range, in: output) else { return nil }
            output.replaceSubrange(range, with: term)
        }
        guard output.range(of: prefix, options: .caseInsensitive) == nil else { return nil }
        return output
    }

    func translate(using translate: (String) async throws -> String) async throws -> String {
        if let exactTerm { return exactTerm }
        let result = try await translate(input)
        if let restored = restore(result) { return restored }
        try Task.checkCancellation()
        return try await translate(source)
    }
}
