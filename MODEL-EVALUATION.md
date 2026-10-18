# 要約モデルの比較（2026-10-18）

資料の短い要約を、指定した言語へ直接生成する用途で比較しました。音声字幕はApple Translationを継続します。

## 方法

このMac（Apple Silicon、24 GiB、macOS 15.3.2、Ollama 0.40.6）で、同じ本番の要約処理・指示・文字数条件を使用。論理命題、単位取得条件、相関と因果、探索計算量、含意、データ量、短い入力処理説明の7つの架空教材を用いました。日本語・英語・簡体字・繁体字を含みます。実際の授業資料や音声は使用していません。

これは少数例の確認であり、総合的なモデル精度の評価や、正確さの保証ではありません。出力が受理された件数だけで正確さを評価していません。回数ごとの揺れ、教材の内容、OCRの誤りによって結果は変わります。並行してビルド・テストを行っていたため、時間は目安です。

## 結果

| モデル | 形式・言語・長さの条件を満たした出力 | 確認した特徴 |
|---|---:|---|
| qwen3:4b | 5/7 | 中国語へ日本語が残る例があり、受理された出力でも4 KiB×3個を4個と誤記。探索計算量では条件の一部を省略。 |
| gemma4:e2b | 5/7 | 英語の論理条件を保つ一方、中国語の箇条書きへ日本語が残る例があった。 |
| qwen3.5:9b | 7/7 | 今回の例では言語混在や個数の取り違えなし。含意・逆・対偶、ソートコスト除外、相関≠因果の要点を保った。繁体字の学術用語に直訳調の表現は残る。 |

## 採用

**Qwen3.5 9B** を資料要約の標準に変更。要約と翻訳をまとめて行えること、今回の比較で数値・論理条件と出力言語がより安定していたことを重視しました。専用の全文翻訳モデルは今回は採用していません。

通常の5例（初回・短文を除く）の要約API時間は約2.1〜2.9秒、短文は約1.0秒、初回は約8.7秒でした。画面取得・OCR・ページ安定待ちは別です。AIの出力は保証されず、誤った要約や不自然な訳語が残り得ます。

モデルは公式の [Ollama Qwen3.5](https://ollama.com/library/qwen3.5:9b) から取得しました。接続先は127.0.0.1固定。リモート情報がないローカルGGUF、またはMLXのsafetensors形式のみを許可します。比較対象の既存モデルは削除していません。アプリがモデルを自動で取得することはありません。

## Qwen3.5 9B の出力

原文は `Tests/ModelComparison.swift`、生の結果は `build/summary-validation/model-comparison*.jsonl` にあります。

### propositions → en（8.67秒）

A proposition is a declarative sentence with a definite truth value.

• Examples include '2 is even' (true) and '3 is even' (false).

• Questions and commands are not propositions.

• 'x is even' lacks a truth value until x is defined.

### condition → zh-Hant（2.63秒）

本課修得必須同時具備高出席率與完成最終課題。

• 修得條件需同時滿足：出席率達 80% 以上且提交最終課題。

• 僅有出席率達標而未提交課題者，無法取得單位的資格。

• 單純出席並非足夠的修得條件。

### correlation → zh-Hans（2.09秒）

正相关现象不能直接推导出因果结论，需警惕潜在的共同影响因素。

• 冰激凌销量与水难事故呈正相关

• 相关性不等于因果关系

• 气温可能是影响两者的共同因素

### complexity → ja（2.73秒）

ソート済み配列で二分探索は対数時間、線形探索は最悪で線形時間かかる。

• 二分探索はソート済み配列を前提とし、各ステップで検索範囲を半分にする。

• 二分探索の比較回数は O(log n)、線形探索は最悪で O(n) である。

• 二分探索の計算量はソートコストを含んでいない。

### implication → en（2.23秒）

The implication p→q is false only when p is true and q is false.

• p→q is true regardless of q's value if p is false.

• The converse q→p may not be true even if p→q is true.

• The contrapositive ¬q→¬p is logically equivalent to the original statement.

### numbers → zh-Hant（2.91秒）

計算檔案大小時，需考慮位元組轉換及實際使用的磁碟空間可能因管理資訊而增加。

• 8 位元等於 1 拜特，本處定義 1 KiB 為 1024 拜特。

• 儲存 3 個 4 KiB 檔案總計為 12 KiB。

• 實際使用的磁碟容量可能因管理資訊而增加。

### compact → en（0.98秒）

Computer processes input and outputs results via screen or sound.
