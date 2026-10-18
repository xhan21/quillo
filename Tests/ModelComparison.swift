import AppKit

// Runs the production summarizer on synthetic lecture excerpts, never on user slides.
// This is a comparison report for human review, not an automatic accuracy score.
@main enum ModelComparison {
    @MainActor static func main() async throws {
        setbuf(stdout, nil)
        _ = NSApplication.shared
        let cases: [(String, CaptionLanguage, Int, String)] = [
            ("propositions", .english, 360, "命題と真理値。命題とは、真か偽かを客観的に判断できる文のこと。『2は偶数である』は真の命題。『3は偶数である』は偽の命題。疑問文や命令文は命題ではない。『xは偶数である』はxの値を定めるまでは真理値が確定しない。"),
            ("condition", .traditionalChinese, 200, "単位の修得条件。出席率が80%以上、かつ最終課題を提出した場合に限り、単位を修得できる。出席率が80%以上でも最終課題が未提出なら単位を修得できない。出席だけでは十分ではない。"),
            ("correlation", .chinese, 200, "相関と因果。アイスの売上と水難事故には正の相関がある。しかし、アイスを食べることが事故の原因だとはいえない。気温が両方に影響する可能性がある。相関があっても因果関係があるとは限らない。"),
            ("complexity", .japanese, 200, "Binary search requires a sorted array. It halves the search range at each step and takes O(log n) comparisons. Linear search does not require sorting and takes O(n) comparisons in the worst case. Sorting cost is not included in the binary-search figure."),
            ("implication", .english, 360, "含意 p→q は、pが真でqが偽の場合だけ偽となる。pが偽の場合はqの値にかかわらず真である。p→qが真でも、その逆q→pが真とは限らない。対偶¬q→¬pは元の命題と同値である。"),
            ("numbers", .traditionalChinese, 200, "データ量の計算。8ビットは1バイト。ここでは1 KiB = 1024バイトとする。4 KiBのファイルを3個保存すると12 KiBとなる。実際に使うディスク容量は管理情報などの分だけ増える場合がある。"),
            ("compact", .english, 120, "入力した情報をコンピュータが処理し、その結果を画面や音で伝えます。")
        ]
        for model in CommandLine.arguments.dropFirst() {
            let local = LocalSlideSummarizer(model: model)
            for (id, target, limit, source) in cases {
                let start = Date()
                var row: [String: Any] = ["model": model, "case": id, "target": target.rawValue, "limit": limit, "source": source]
                do { row["text"] = try await local.summarize(.init(source: source, target: target, characterLimit: limit)); row["ok"] = true }
                catch { row["error"] = String(describing: error); row["ok"] = false }
                row["seconds"] = Date().timeIntervalSince(start)
                print(String(data: try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]), encoding: .utf8)!)
            }
        }
    }
}
