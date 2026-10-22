# 開発と更新の引き継ぎ

## 説明書の案内

- [日本語README](../README.md) ／ [English README](../README.en.md)：作った理由・機能・動作画面。短い箇条書きを中心に保ち、機能・導入条件・確認範囲・開発者表記は両言語で揃える。
- [導入手順](SETUP.md) ／ [使い方・困ったとき](USER_GUIDE.md)：利用者向け。
- [内部の仕組み](ARCHITECTURE.md) ／ [用語辞書の形式](GLOSSARIES.md)：開発・拡張向け。
- [確認記録](VALIDATION.md) ／ [変更履歴](../CHANGELOG.md)：実際に確認した範囲。
- 公開画像は`docs/images/`。利用者から掲載を依頼されたサンプル画面のみを使い、個人の教材・字幕ログは含めない。
- 開発者とChatGPT（愛称Hedwig）の役割は[シリーズ紹介](https://github.com/xhan21/hedwig-tools)に集約。各言語のREADMEにはシリーズへのリンクだけを置き、助手についての説明を重複させない。

## 別のチャットで続ける

このリポジトリのURLと、直したい点を伝えてください。たとえば「Quilloの続きです。README、AGENTS.md、docs/MAINTENANCE.mdを読んでから、字幕の○○を改善してください」で、仕様・構成・確認記録を共有できます。チャットの会話そのものはGitHubに保存されないため、重要な決定はこの文書やCHANGELOGへ反映します。

更新は必要なときに依頼して行います。定期確認・自動更新・自動モデル取得は設定していません。

## 構成

| 担当 | 主なファイル |
|---|---|
| 起動、メニュー、設定画面 | Sources/Main.swift、ControlView.swift |
| 音声認識とライブ字幕 | SpeechCapture.swift、AppModel.swift、CaptionPlayback.swift |
| 字幕の表示・外観 | OverlayController.swift、CaptionAppearance.swift、SentenceCaptionReading.swift |
| 画面選択・範囲指定・OCR | SlideCapture.swift、SlideRegionSelection.swift、SlideRegionEditing.swift、SlideAnalyzer.swift |
| 資料の読み順・要約 | SlideReadingOrder.swift、SlideTranslationModel.swift、SlideSummary.swift |
| 要約パネル・自動サイズ調整 | SlideTranslationPanel.swift、SlidePanelLayout.swift、SlidePanelPresentation.swift |
| 資料別用語辞書 | MaterialGlossary.swift、GlossaryStore.swift、GlossaryView.swift |
| 動作確認 | Tests/、docs/VALIDATION.md |

旧実装由来のファイル名にTranslationやKotobaが残っています。表示名はQuilloですが、既存設定の引き継ぎのためアプリ識別子jp.xuhan.KotobaLocalと内部実行ファイル名KotobaLocalは維持します。名称整理だけを理由に変更しないでください。

## 翻訳・要約の更新

音声字幕の認識と翻訳はmacOS付属のSpeech／Translationです。翻訳モデルは同梱せず、利用者の資料別辞書を追加できる構成です。macOSと利用言語データの提供状態、AppleのAPI変更を確認した上でアプリの対応を調整します。OS更新は授業中に行わず、本人のタイミングに合わせてください。

0.1.4から音声入力は本人の希望で日本語・英語のみ。中国語の音声モデル取得を利用者に求めないでください。翻訳先・資料の言語・文字入力は4言語を維持し、話す言語と資料の言語を独立させています。表示先のみ共通です。翻訳用モデルの取得完了と、音声認識の利用可否は別に確認します。

任意の入力文補正は`CaptionCorrection.swift`、字幕への適用は`AppModel.swift`にあります。0.1.15から本人の意図に合わせ、翻訳後の文ではなく音声認識・文字入力の原文を補正します。入力と初回訳は待たせず、0.1.16では約0.45秒入力が安定した時点または話の区切りで、文脈に沿った文字抜け・誤記修正を行い、採用した原文から訳し直します。原文のみ・同じ入出力言語でも補正できます。認識の版と翻訳の版を分け、補正前の訳が遅れて届いても戻さず、履歴の同じ位置へ反映します。数字・否定・用語・変更量を全件確認し、1文字より大きな変更のみ追加のAI照合を行います。補正の期限は約4秒。取得済みモデルを先に読み込み、入力が変化した後の古い補正は捨てます。接続の保護は`LocalOllama.swift`で資料要約と共通。補正設定は初期値オフ、既存のオン／オフは引き継ぎます。

資料要約は別途導入したOllamaと取得済みのローカルモデルを利用します。現在の標準はqwen3.5:9bです。モデル選定の根拠は[MODEL-EVALUATION.md](../MODEL-EVALUATION.md)を参照してください。モデル名が同じでも配布内容が変わる場合があるため、更新時は実際の形式・ローカル実行・4言語・数値と条件・速度・メモリ使用量を確認し、動作確認後に標準を変更します。

共通語は`Sources/CommonVocabulary.swift`、個人の授業別用語は外部JSONです。0.1.17から`GlossaryStore.effective`で共通＋授業別を合成し、認識・原文補正・資料要約へ渡します。字幕の固定訳語には`translationGlossary`を使い、日常表現を固定訳にしません。元の辞書ファイルや選択IDは変更せず、共通語との衝突は授業別を優先します。

資料別の用語辞書は実装済みです。形式・保存先・字幕と要約への適用はGLOSSARIES.mdを参照してください。教材本文・発表者メモ・個人の辞書をGitHubへ入れないでください。Mac上の既存辞書を確認してから必要な語だけ追加し、同じIDで更新します。

## 言語の動作確認

履歴のオン／オフと表示数（1文／2文）は表示だけの設定です。内部の履歴記録は続け、マイク・翻訳セッションを作り直さないでください。発話IDに対応する履歴枠へ遅延翻訳を反映する回帰テストも維持します。

マイクの履歴変更では、句点も新しい認識IDも来ない累積途中結果を必ずテストしてください。`SpeechPhraseTests`と`PlaybackIntegrationTests`で確認します。`zsh Tools/build-speech-history-check.sh`で作る`build/QuilloSpeechHistoryCheck.app`は、架空の合成音声を実Apple Speechへ流し、実Translationと本番の字幕表示へつなげます。マイクを使わず、結果は`/private/tmp/quillo-speech-history-check.json`へ出力します。`zsh Tools/build-speech-history-check.sh --short-start`は、冒頭の待ち時間を置かず「大丈夫です」から始め、認識原文と字幕の先頭が残るかを確認します。これは実際の教室音声の精度確認とは別です。

英語・中国語訳の読みやすさ表示を変更した場合は`SentenceCaptionReadingTests`と`PlaybackIntegrationTests`を実行します。`zsh Tools/build-reading-check.sh`で作る`build/QuilloReadingCheck.app`は、架空の日本語・英語を実Apple Translationへ渡し、英語・中国語（簡体字／繁体字）の訳の標準表示を確認できます。途中認識を模した入力であり、マイクは使用しません。結果は`/private/tmp/quillo-caption-reading-check.json`です。0.1.15では入力文の補正に変更。`CaptionCorrectionTests`で即時表示・原文のみ・原文補正から再翻訳・オフ復帰・履歴・古い原文や訳の拒否を確認し、`build/caption-correction-tests --live`で架空の誤字・曖昧な断片・数値と否定を実モデルへ渡します。入力の正確さを機械的確認だけで判断しないでください。

範囲編集を変更した場合は`SlideRegionEditingTests`に加え、`zsh Tools/build-region-check.sh`で作る`build/QuilloRegionCheck.app`で、移動・角と辺の拡縮・元に戻す・キャンセルを確認します。これは架空のスライドを使う画面で、他アプリの画面共有やマイクは使用しません。

言語の処理を変更した場合は、通常の回帰テストに加えて次の確認を行います。どちらも架空の文章を使い、マイクや他アプリの画面にはアクセスしません。

- `zsh Tools/build-language-check.sh`で作成した`build/QuilloLanguageCheck.app`を開く。同じ設定画面で16通りを順に切り替え、実際のApple Translationと中国語の字体変換を確認。結果は`/private/tmp/quillo-caption-matrix.json`。初回は翻訳データの準備後に再実行する。
- `build/language-coverage-tests --live`：4言語のサンプル画像をVisionで読み取り、ローカルOllamaで各4言語の要約を生成。結果は`/private/tmp/quillo-summary-matrix.json`。
- 上記はマイクの言語別認識精度の確認ではない。音声データの準備状態・実際の音声認識は別に記録する。

## 開発と配布手順

1. 現在のコード、未保存の変更、CHANGELOGを確認する。
2. 目的に合う変更と回帰テストを行う。`zsh test.sh` はMac上で実行する。実際のVision処理を使うため、制限された実行環境では失敗する場合がある。単なる表示名変更にマイクテストは不要。
3. `zsh build.sh` でbuild/Quillo.appを生成する。`codesign --verify --deep --strict build/Quillo.app` で署名を確認する。
4. アイコンを変更する場合はTools/CreateIcon.swiftからiconsetを生成し、macOSのiconutilでResources/AppIcon.icnsへ変換してからビルドする。
5. インストール済みQuilloを終了する。`/Applications/Quillo.app` に別アプリが存在しないか識別子を確認してから、ビルドを置き換える。以前の版は復元できる場所へ保存する。起動中の実行ファイルを書き換えない。
6. アプリケーション内のQuilloを起動し、設定が維持されたこと、変更した機能が動くことを確認する。画面選択・マイクは本人の操作または許可済みの確認範囲で再開する。
7. CHANGELOGと確認記録を更新してコミットする。一般配布用のリリース、公開範囲、モデル配布は本人の意図を確認して進める。

個人Mac用は固定のローカル開発署名を使用します。`Tools/setup-local-signing.py`で一度だけ準備し、証明書の公開フィンガープリントをApplication Support/Quillo/Signing/identity.sha1、書き出し不可の秘密鍵をログインキーチェーンへ保存します。毎回のビルドは同じキーを使用し、設定済みのキーがない場合は失敗させます。キーを作り直すと権限が引き継がれなくなるため、勝手に再生成・削除しないでください。TCCデータベースやシステムの信頼設定は変更しません。

Appleの公証済み一般配布版ではありません。ローカル証明書で署名したバイナリは一般配布せず、他のMac向けに配布する段階ではDeveloper ID署名・公証と、対応環境での確認を別途行います。GitHubへのソース掲載だけでは自動更新は有効になりません。
