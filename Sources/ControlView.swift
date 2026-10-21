import SwiftUI
import Translation

struct ControlView: View {
    @ObservedObject var model: AppModel
    @State private var section = 0
    @State private var appearanceSection = 0
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Q").font(.system(size: 25, weight: .bold)).foregroundStyle(Color.kotobaLime).frame(width: 40, height: 40).background(Color.kotobaGreen).clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Quillo").font(.system(size: 19, weight: .semibold))
                    Text("授業に、字幕と要約を。").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("画面", selection: $section) {
                    Text("授業").tag(0)
                    Text("設定").tag(1)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 220)
                Button { model.helpVisible = true } label: { Image(systemName: "questionmark.circle").font(.system(size: 17)) }
                    .buttonStyle(.plain).accessibilityLabel("使い方")
            }.padding(22)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if section == 0 {
                        LanguageSettingsCard(model: model, slides: model.slides) { section = 1; appearanceSection = 2 }
                        speechCard
                        SlideTranslationCard(model: model.slides)
                        Text("学生に見せるときは、資料・字幕・要約を含む画面全体を投影・共有してください。")
                            .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    } else {
                        Picker("設定の対象", selection: $appearanceSection) {
                            Text("音声字幕").tag(0)
                            Text("資料の要約").tag(1)
                            Text("用語辞書").tag(2)
                        }.pickerStyle(.segmented).labelsHidden()
                        if appearanceSection == 0 { appearanceCard }
                        else if appearanceSection == 1 { SummaryAppearanceCard(model: model.slides) }
                        else { GlossarySettings(store: model.glossary, isListening: model.isListening || model.isStartingMic) }
                        DisclosureGroup("動作確認・字幕ログ") {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack(spacing: 12) {
                                    Button(model.isDemoPlaying ? "字幕デモを停止" : "字幕デモ") { model.toggleDemo() }
                                    Button("要約デモ") { model.slides.showDemo() }
                                }.buttonStyle(.bordered)
                                inputCard
                                if !model.logs.isEmpty { transcriptCard }
                                else { Text("字幕ログは、マイクや文字入力を使うと表示されます。").font(.system(size: 11)).foregroundStyle(.secondary) }
                            }.padding(.top, 14)
                        }.font(.system(size: 12)).card()
                        Text("音声字幕：macOSの音声認識・翻訳 ／ 資料の要約：Mac内のAI").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }.padding(22)
            }
        }
        .background(Color.kotobaPaper).preferredColorScheme(.light).tint(Color.kotobaGreen)
        .frame(minWidth: 680, idealWidth: 760, minHeight: 650)
        .background {
            if let configuration = model.translationConfiguration {
                CaptionTranslationHost(model: model, configuration: configuration, sessionID: model.translationSessionID)
                    .id(model.translationSessionID)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refreshSpeechReadiness() }
        .sheet(isPresented: $model.helpVisible) { HelpView() }
    }
    private var captionMode: Binding<String> {
        Binding(get: { model.translationEnabled ? model.displayMode.rawValue : "original" }, set: { value in
            model.setCaptionMode(CaptionDisplayMode(rawValue: value))
        })
    }
    private var speechCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Label("音声字幕", systemImage: "mic").font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(model.isListening ? "マイク使用中" : model.isDemoPlaying ? "デモ再生中" : "停止中").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Button { model.toggleMic() } label: { Label(model.microphoneActionTitle, systemImage: model.isListening ? "stop.fill" : "mic.fill") }
                    .buttonStyle(GreenButtonStyle(destructive: model.isListening))
                if model.overlayVisible {
                    Button("字幕を隠す") { model.hideOverlay() }.buttonStyle(PlainActionStyle())
                } else if model.isListening || model.isStartingMic {
                    Button("字幕を再表示") { model.ensureOverlay() }.buttonStyle(PlainActionStyle())
                }
                Spacer()
                Button("消去") { model.clearCaption() }.font(.system(size: 11)).buttonStyle(.plain)
            }
            Picker("字幕に表示する内容", selection: captionMode) {
                Text("原文のみ").tag("original")
                Text("翻訳のみ").tag(CaptionDisplayMode.translationOnly.rawValue)
                Text("原文 ＋ 翻訳").tag(CaptionDisplayMode.bilingual.rawValue)
            }.pickerStyle(.segmented).labelsHidden()
            Text(model.status).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !model.speechLanguageReady {
                Text("\(model.speechLanguage.dictationName)の端末内音声認識を利用できません。Macの「システム設定 → キーボード → 音声入力 → 言語」を確認してください。文字入力・資料要約は使えます。")
                    .font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            if model.requiresTranslation {
                HStack {
                    Text(model.translationStatus).font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    if !model.translationReady || model.liveTranslationFailed {
                        Button(model.preparingTranslation ? "準備をやり直す" : "翻訳を準備") { model.retryTranslation() }
                            .font(.system(size: 11)).buttonStyle(.bordered)
                    }
                }
            }
        }.card()
    }
    private var appearanceCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("音声字幕の見た目").font(.system(size: 15, weight: .semibold))
            HStack {
                Button(model.microphoneActionTitle) { model.toggleMic() }
                if model.overlayVisible { Button("字幕を隠す") { model.hideOverlay() } }
                else if model.isListening || model.isStartingMic { Button("字幕を再表示") { model.ensureOverlay() } }
                Toggle("位置を固定", isOn: Binding(get: { model.positionLocked }, set: { _ in model.toggleLock() })).toggleStyle(.switch)
                Spacer()
                Button("画面下に戻す") { model.overlay?.moveToSelectedScreen() }
            }.font(.system(size: 11)).buttonStyle(.bordered)
            Text(model.positionLocked ? "固定中は、字幕の下にあるスライドを操作できます。" : "字幕の背景をドラッグして移動、右下のつまみでサイズを変更できます。")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            HStack {
                Toggle("履歴を表示", isOn: $model.historySettings.enabled).toggleStyle(.switch)
                Spacer()
                Picker("表示する履歴", selection: $model.historySettings.count) {
                    Text("1文").tag(1)
                    Text("2文").tag(2)
                }.pickerStyle(.segmented).frame(width: 160).disabled(!model.historySettings.enabled)
            }.font(.system(size: 12))
            Text("現在の文に加え、直前の1〜2文を薄く表示します。オフでは現在の文だけを表示します。")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 24) {
                ValueAdjustment(title: "原文の文字サイズ", value: $model.appearance.sourceFontSize, range: 14...90, unit: "pt")
                ValueAdjustment(title: "翻訳の文字サイズ", value: $model.appearance.translationFontSize, range: 14...90, unit: "pt")
            }
            Divider()
            BackgroundChoices(background: $model.appearance.background)
            ValueAdjustment(title: "背景の濃さ", value: $model.appearance.opacity, range: 0...1, step: 0.01, unit: "%", multiplier: 100)
            DisclosureGroup("パネルのサイズ・表示先") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 24) {
                        ValueAdjustment(title: "幅", value: $model.appearance.width, range: 320...2000, step: 10, unit: "pt")
                        ValueAdjustment(title: "高さ", value: $model.appearance.height, range: model.minimumPanelHeight...900, step: 10, unit: "pt").disabled(model.appearance.automaticHeight)
                    }
                    Toggle("高さを現在の文と履歴に合わせる", isOn: $model.appearance.automaticHeight)
                    Picker("表示画面", selection: $model.selectedScreen) { ForEach(Array(model.screens.enumerated()), id: \.offset) { offset, screen in Text(screen.localizedName).tag(offset) } }
                        .onChange(of: model.selectedScreen) { _, _ in model.overlay?.moveToSelectedScreen() }
                }.padding(.top, 12)
            }.font(.system(size: 11))
            HStack {
                Text("非常に長い訳文は区切りから続きを表示。全文は字幕ログに残ります。").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button("見た目を標準に戻す") { model.appearance = CaptionAppearance() }.font(.system(size: 10)).buttonStyle(.plain)
            }
        }.card().onChange(of: model.appearance) { _, _ in model.updateAppearance() }
    }
    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("文字を入力して字幕を確認").font(.system(size: 11)).foregroundStyle(.secondary)
            Picker("文字入力の言語", selection: $model.sourceLanguage) {
                ForEach(CaptionLanguage.allCases) { Text($0.name).tag($0) }
            }.disabled(model.isListening || model.isStartingMic)
                .onChange(of: model.sourceLanguage) { _, _ in model.languageChanged() }
            HStack {
                TextField("字幕にしたい文章", text: $model.typedText).textFieldStyle(.roundedBorder).onSubmit { model.sendTypedCaption() }.accessibilityLabel("字幕にする文章")
                Button("表示") { model.sendTypedCaption() }.disabled(model.typedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack { Text("字幕ログ").font(.system(size: 12, weight: .semibold)); Spacer(); Button("テキストで保存") { model.exportTranscript() } }
            ForEach(model.logs.suffix(3).reversed()) { line in
                VStack(alignment: .leading, spacing: 3) {
                    Text(line.source).font(.system(size: 11)).lineLimit(2)
                    if !line.translation.isEmpty { Text(line.translation).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2) }
                    if line.translationIncomplete { Text("翻訳未完了・途中の結果").font(.system(size: 9)).foregroundStyle(.secondary) }
                }
            }
            Text("全文は「テキストで保存」で取り出せます。保存しなければ、ログは終了時に消えます。")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
}

private struct LanguageSettingsCard: View {
    @ObservedObject var model: AppModel
    @ObservedObject var slides: SlideTranslationModel
    let showGlossary: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("言語の設定", systemImage: "globe").font(.system(size: 15, weight: .semibold))
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Label("話す言語", systemImage: "mic").font(.system(size: 12, weight: .medium))
                        Picker("話す言語", selection: Binding(get: { model.speechLanguage }, set: { model.setSpeechLanguage($0) })) {
                            ForEach(CaptionLanguage.speechInputLanguages) { Text($0.name).tag($0) }
                        }.labelsHidden().disabled(model.isListening || model.isStartingMic)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Label("資料の言語", systemImage: "doc.text").font(.system(size: 12, weight: .medium))
                        Picker("資料の言語", selection: Binding(get: { slides.source }, set: { slides.configure(source: $0, target: model.targetLanguage) })) {
                            ForEach(CaptionLanguage.allCases) { Text($0.name).tag($0) }
                        }.labelsHidden()
                    }
                }.frame(maxWidth: .infinity)
                Image(systemName: "arrow.right").font(.system(size: 18)).foregroundStyle(Color.kotobaGreen)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 7) {
                    Text("学生に見せる言語").font(.system(size: 12, weight: .semibold))
                    Picker("学生に見せる言語", selection: $model.targetLanguage) {
                        ForEach(CaptionLanguage.allCases) { Text($0.name).tag($0) }
                    }.labelsHidden().onChange(of: model.targetLanguage) { _, _ in model.languageChanged() }
                    Text("字幕の翻訳・資料の要約に共通")
                        .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("音声入力は日本語・英語。資料と表示は中国語（簡体字・繁体字）も選べます。")
                .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("資料の言語・学生に見せる言語を変えたら、資料の画面を選び直してください。")
                .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Divider()
            HStack {
                GlossaryPicker(store: model.glossary).disabled(model.isListening || model.isStartingMic)
                Button("用語を確認", action: showGlossary).font(.system(size: 11))
            }
        }.card()
    }
}

// Keep session identity separate from the controls, so rebuilding a cancelled
// translation task does not reset the selected settings tab or text field.
private struct CaptionTranslationHost: View {
    let model: AppModel
    let configuration: TranslationSession.Configuration
    let sessionID: UUID
    var body: some View {
        Color.clear.frame(width: 1, height: 1)
            .translationTask(configuration) { session in
                await model.runTranslation(session, sessionID: sessionID)
            }
    }
}

struct ValueAdjustment: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    let unit: String
    var multiplier: Double = 1
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int((value * multiplier).rounded())) \(unit)").monospacedDigit().font(.system(size: 11))
                Stepper(title, value: $value, in: range, step: step).labelsHidden().accessibilityLabel(title + "を調整")
            }
            Slider(value: $value, in: range, step: step).accessibilityLabel(title)
        }
    }
}
struct BackgroundChoices: View {
    @Binding var background: CaptionRGB
    var body: some View {
        HStack(spacing: 9) {
            Text("背景色").font(.system(size: 11)).foregroundStyle(.secondary)
            preset("深緑", color: .forest); preset("黒", color: .black); preset("白", color: .white)
            Spacer()
            ColorPicker("その他", selection: Binding(get: { background.color }, set: { background = CaptionRGB($0) }), supportsOpacity: false).font(.system(size: 11)).fixedSize()
        }
    }
    private func preset(_ title: String, color: CaptionRGB) -> some View {
        Button { background = color } label: {
            HStack(spacing: 5) {
                Circle().fill(color.color).frame(width: 12, height: 12).overlay(Circle().stroke(Color.gray.opacity(0.3)))
                Text(title).font(.system(size: 11))
            }.padding(.horizontal, 9).padding(.vertical, 6)
                .background(background == color ? Color.kotobaGreen.opacity(0.10) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.kotobaGreen.opacity(background == color ? 0.5 : 0.16)))
        }.buttonStyle(.plain).accessibilityLabel("背景色：" + title)
    }
}
struct GreenButtonStyle: ButtonStyle {
    var destructive = false
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .semibold)).padding(.horizontal, 16).padding(.vertical, 10).foregroundStyle(.white).background((destructive ? Color(red: 0.6, green: 0.25, blue: 0.2) : Color.kotobaGreen).opacity(configuration.isPressed ? 0.8 : 1)).clipShape(RoundedRectangle(cornerRadius: 8)).opacity(isEnabled ? 1 : 0.4)
    }
}
struct PlainActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 11, weight: .medium)).padding(.horizontal, 12).padding(.vertical, 9).background(configuration.isPressed ? Color.kotobaGreen.opacity(0.08) : .white).clipShape(RoundedRectangle(cornerRadius: 7)).overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.kotobaGreen.opacity(0.17))).opacity(isEnabled ? 1 : 0.4)
    }
}
extension View { func card() -> some View { self.padding(17).background(.white).clipShape(RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.kotobaGreen.opacity(0.10))) } }

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("授業での使い方").font(.system(size: 22, weight: .semibold)); Spacer(); Button("閉じる") { dismiss() } }
            instruction("1", "言語を選ぶ", "「言語の設定」で、話す言語・資料の言語と、学生に見せる言語を選びます。音声入力は日本語・英語。資料と表示は中国語（簡体字／繁体字）も選べます。学生に見せる言語は、字幕の翻訳・資料の要約で共通です。")
            instruction("2", "音声字幕を使う", "「話して字幕を出す」で開始します。翻訳の初回だけ言語データの準備が必要です。原文のみ・翻訳のみ・両方を選べます。長い発話は自動で最新の行に進みます。")
            instruction("3", "資料の要約を使う", "「資料の画面を選ぶ」で資料のウィンドウを選択し、プレビューで資料の部分をドラッグします。選んだ文章の要点を、表示する言語で短くまとめます。図そのものは説明しません。")
            instruction("4", "見た目を整えて投影する", "字幕・要約は背景をドラッグして移動、右下のつまみでサイズを変えられます。「設定」で文字サイズ・背景・位置固定を調整します。学生には資料と字幕・要約が入る画面全体を共有し、この設定画面は別画面に置くか閉じてください。")
            Divider()
            Text("閉じた設定画面は、メニューバーの吹き出し、Dockのアプリアイコン、または⌘ ,で開けます。字幕の表示切替は⌃⌥⌘ K、字幕の位置固定は⌃⌥⌘ Lです。")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Text("音声は録音保存しません。字幕ログは保存を選んだときだけファイルにします。資料要約はMac内のOllamaで処理し、クラウドのAPIは使いません。AIによる読み違いや要約の誤りはあり得るため、条件・数式などは元の資料も確認してください。")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }.padding(28).frame(width: 570)
    }
    private func instruction(_ number: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Text(number).font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.kotobaGreen).frame(width: 24)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(text).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
