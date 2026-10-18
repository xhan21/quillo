# 開発と更新の引き継ぎ

## 説明書の案内

- [日本語README](../README.md) ／ [English README](../README.en.md)：作った理由・機能・動作画面。短い箇条書きを中心に保ち、機能・導入条件・確認範囲・開発者表記は両言語で揃える。
- [導入手順](SETUP.md) ／ [使い方・困ったとき](USER_GUIDE.md)：利用者向け。
- [内部の仕組み](ARCHITECTURE.md) ／ [用語辞書の形式](GLOSSARIES.md)：開発・拡張向け。
- [確認記録](VALIDATION.md) ／ [変更履歴](../CHANGELOG.md)：実際に確認した範囲。
- 公開画像は`docs/images/`。利用者から掲載を依頼されたサンプル画面のみを使い、個人の教材・字幕ログは含めない。

## 別のチャットで続ける

このリポジトリのURLと、直したい点を伝えてください。たとえば「Quilloの続きです。README、AGENTS.md、docs/MAINTENANCE.mdを読んでから、字幕の○○を改善してください」で、仕様・構成・確認記録を共有できます。チャットの会話そのものはGitHubに保存されないため、重要な決定はこの文書やCHANGELOGへ反映します。

更新は必要なときに依頼して行います。定期確認・自動更新・自動モデル取得は設定していません。

## 構成

| 担当 | 主なファイル |
|---|---|
| 起動、メニュー、設定画面 | Sources/Main.swift、ControlView.swift |
| 音声認識とライブ字幕 | SpeechCapture.swift、AppModel.swift、CaptionPlayback.swift |
| 字幕の表示・外観 | OverlayController.swift、CaptionAppearance.swift |
| 画面選択・範囲指定・OCR | SlideCapture.swift、SlideRegionSelection.swift、SlideAnalyzer.swift |
| 資料の読み順・要約 | SlideReadingOrder.swift、SlideTranslationModel.swift、SlideSummary.swift |
| 要約パネル・自動サイズ調整 | SlideTranslationPanel.swift、SlidePanelLayout.swift、SlidePanelPresentation.swift |
| 資料別用語辞書 | MaterialGlossary.swift、GlossaryStore.swift、GlossaryView.swift |
| 動作確認 | Tests/、docs/VALIDATION.md |

旧実装由来のファイル名にTranslationやKotobaが残っています。表示名はQuilloですが、既存設定の引き継ぎのためアプリ識別子jp.xuhan.KotobaLocalと内部実行ファイル名KotobaLocalは維持します。名称整理だけを理由に変更しないでください。

## 翻訳・要約の更新

音声字幕の認識と翻訳はmacOS付属のSpeech／Translationです。翻訳モデルは同梱せず、利用者の資料別辞書を追加できる構成です。macOSと利用言語データの提供状態、AppleのAPI変更を確認した上でアプリの対応を調整します。OS更新は授業中に行わず、本人のタイミングに合わせてください。

資料要約は別途導入したOllamaと取得済みのローカルモデルを利用します。現在の標準はqwen3.5:9bです。モデル選定の根拠はMODEL-EVALUATION.mdを参照してください。モデル名が同じでも配布内容が変わる場合があるため、更新時は実際の形式・ローカル実行・4言語・数値と条件・速度・メモリ使用量を確認し、動作確認後に標準を変更します。

資料別の用語辞書は実装済みです。形式・保存先・字幕と要約への適用はGLOSSARIES.mdを参照してください。教材本文・発表者メモ・個人の辞書をGitHubへ入れないでください。Mac上の既存辞書を確認してから必要な語だけ追加し、同じIDで更新します。

## 開発と配布手順

1. 現在のコード、未保存の変更、CHANGELOGを確認する。
2. 目的に合う変更と回帰テストを行う。`zsh test.sh` はMac上で実行する。実際のVision処理を使うため、制限された実行環境では失敗する場合がある。単なる表示名変更にマイクテストは不要。
3. `zsh build.sh` でbuild/Quillo.appを生成する。`codesign --verify --deep --strict build/Quillo.app` で署名を確認する。
4. アイコンを変更する場合はTools/CreateIcon.swiftからiconsetを生成し、macOSのiconutilでResources/AppIcon.icnsへ変換してからビルドする。
5. インストール済みQuilloを終了する。`/Applications/Quillo.app` に別アプリが存在しないか識別子を確認してから、ビルドを置き換える。以前の版は復元できる場所へ保存する。起動中の実行ファイルを書き換えない。
6. アプリケーション内のQuilloを起動し、設定が維持されたこと、変更した機能が動くことを確認する。画面選択・マイクは本人の操作または許可済みの確認範囲で再開する。
7. CHANGELOGと確認記録を更新してコミットする。一般配布用のリリース、公開範囲、モデル配布は本人の意図を確認して進める。

現状はApple Silicon向けのアドホック署名で、Appleの公証済み一般配布版ではありません。他のMac向けに配布する段階では署名・公証と、対応環境での確認を別途行います。GitHubへのソース掲載だけでは自動更新は有効になりません。
