import SwiftUI

struct SlideTranslationCard: View {
    @ObservedObject var model: SlideTranslationModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("資料の要約", systemImage: "text.alignleft").font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(model.isRunning ? "読み取り中" : "停止中").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Text("選んだ範囲の内容を短くまとめ、別の窓に表示します。")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button { model.chooseScreen() } label: { Label(model.isSelecting ? "画面選択を開き直す" : model.isRunning ? "画面を変更" : "資料の画面を選ぶ", systemImage: "viewfinder") }
                    .buttonStyle(GreenButtonStyle())
                if model.canEditRegions {
                    Button(model.isEditingRegions ? "範囲選択に戻る" : "範囲を変更") { model.editRegions() }.buttonStyle(PlainActionStyle())
                }
                Spacer()
                if model.isRunning { Button("停止") { model.stop() }.buttonStyle(PlainActionStyle()) }
            }
            if model.isRunning || model.isSelecting {
                Text(model.selectedName).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                if !model.canEditRegions || model.isEditingRegions || model.regions.isEmpty {
                    Text(regionGuidance).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("画面を選ぶ → プレビューで資料の部分を囲む → 要約を表示")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if !model.regions.isEmpty {
                HStack(spacing: 12) {
                    Button(model.panelVisible ? "要約を隠す" : "要約を表示") { model.togglePanel() }
                    Button("要約し直す") { model.resummarize() }
                    Spacer()
                    Text("選択範囲：\(model.regions.count)か所").foregroundStyle(.secondary)
                }.font(.system(size: 11)).buttonStyle(.bordered)
                Text(model.panelStatus).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.card()
    }
    private var regionGuidance: String {
        if !model.isRunning { return "Macの画面選択で、資料のウィンドウを選んで共有してください。" }
        if !model.canEditRegions { return "選んだ画面を読み込み中です。資料を開いたままお待ちください。" }
        if model.isEditingRegions { return "枠の中をドラッグで移動、角や辺でサイズを調整できます。" }
        return "「範囲を変更」で、枠の移動・サイズ調整・追加ができます。"
    }
}

struct SummaryAppearanceCard: View {
    @ObservedObject var model: SlideTranslationModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("資料の要約の見た目").font(.system(size: 15, weight: .semibold))
            HStack {
                Button(model.panelVisible ? "要約を隠す" : "要約を表示") { model.togglePanel() }
                Toggle("位置を固定", isOn: $model.positionLocked).toggleStyle(.switch)
                Spacer()
                Button("位置と大きさを戻す") { model.resetPanelPosition() }
            }.font(.system(size: 11)).buttonStyle(.bordered)
            Text(model.positionLocked ? "固定中は、要約の下にあるスライドを操作できます。" : "要約の背景をドラッグして移動、右下のつまみでサイズを変更できます。")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            ValueAdjustment(title: "文字サイズの上限", value: $model.fontSize, range: 12...32, unit: "pt")
            Text("長さに合わせて文字サイズを自動調整。小さい窓では、さらに短く要約します。")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Divider()
            BackgroundChoices(background: $model.background)
            ValueAdjustment(title: "背景の濃さ", value: $model.opacity, range: 0...1, step: 0.01, unit: "%", multiplier: 100)
        }.card()
    }
}
