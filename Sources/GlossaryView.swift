import SwiftUI

struct GlossaryPicker: View {
    @ObservedObject var store: GlossaryStore
    var body: some View {
        Picker("授業別の辞書", selection: Binding(get: { store.selectedID }, set: { store.select($0) })) {
            Text("共通辞書のみ").tag("")
            ForEach(store.dictionaries) { Text($0.name + "（\($0.entries.count)語）").tag($0.id) }
        }
    }
}

struct GlossarySettings: View {
    @ObservedObject var store: GlossaryStore
    let isListening: Bool
    @State private var search = ""
    @State private var showingCommon = true
    private var entries: [GlossaryEntry] {
        let all = showingCommon ? store.common.entries : store.selected?.entries ?? []
        return search.isEmpty ? all : all.filter { $0.terms.values.contains { $0.localizedCaseInsensitiveContains(search) }
            || $0.aliases.values.flatMap { $0 }.contains { $0.localizedCaseInsensitiveContains(search) } }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("共通辞書 ＋ 授業別の辞書", systemImage: "character.book.closed").font(.system(size: 15, weight: .semibold))
            Text("共通辞書はいつも使用します。授業別の辞書を選ぶと、両方を使います。同じ言葉の訳語は授業別を優先します。")
                .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            HStack {
                GlossaryPicker(store: store)
                Button("辞書を追加・更新…") { store.chooseImport() }
            }.disabled(isListening)
            Text(isListening ? "授業別の辞書を変えるときは、音声字幕をいったん停止してください。" : "用語は音声認識・入力文の補正・字幕翻訳・資料要約で使います。個人の授業別辞書はMacに保存され、アプリ更新でも残ります。")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Picker("確認する辞書", selection: $showingCommon) {
                Text("共通（\(store.common.entries.count)語）").tag(true)
                Text("授業別（\(store.selected?.entries.count ?? 0)語）").tag(false)
            }.pickerStyle(.segmented)
            if showingCommon {
                Text("日常表現の認識候補（\(CommonVocabulary.conversation.count)件）\n" + CommonVocabulary.conversation.joined(separator: "・"))
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text("日常表現の訳は文脈に合わせます。「丈夫」を一律に「大丈夫」に置き換えることはしません。")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if showingCommon || store.selected != nil {
                TextField("用語を探す", text: $search).textFieldStyle(.roundedBorder)
                Grid(alignment: .leading, horizontalSpacing: 12) {
                    GridRow { ForEach(CaptionLanguage.allCases) { Text($0.name).frame(maxWidth: .infinity, alignment: .leading) } }
                }.font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                            HStack(alignment: .top, spacing: 12) {
                                ForEach(CaptionLanguage.allCases) { language in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(entry.term(language) ?? "—").textSelection(.enabled)
                                        if let aliases = entry.aliases[language.rawValue], !aliases.isEmpty {
                                            Text(aliases.joined(separator: "・")).font(.system(size: 10)).foregroundStyle(.secondary).textSelection(.enabled)
                                        }
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }.font(.system(size: 12))
                            Divider()
                        }
                    }
                }.frame(height: 270)
                Text("\(entries.count)語を表示 · 訳語は表示する言語に合わせて切り替わります。")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                Text("辞書ファイルを追加すると、このMacに保存されます。資料の文章や音声は辞書に保存しません。")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            if !store.message.isEmpty { Text(store.message).font(.system(size: 11)).foregroundStyle(.secondary) }
            Text("用語の一致を補助する機能です。音声認識や訳文の正確さを保証するものではありません。字幕では用語を保持できないとき、通常の翻訳に戻ります。")
                .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.card()
    }
}
