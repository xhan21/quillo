import AppKit
import SwiftUI
import Combine

private struct SlidePage {
    let blocks: [SlideTextBlock]
}

@MainActor
final class SlideTranslationModel: ObservableObject {
    @Published private(set) var status = "資料の画面と範囲を選ぶと、別パネルに要約を表示します。"
    @Published private(set) var selectedName = "画面は未選択"
    @Published private(set) var isRunning = false
    @Published private(set) var isDemo = false
    @Published private(set) var isSelecting = false
    @Published private(set) var pageRevision = 0
    let summary = SlideSummaryModel()
    private var summarySubscription: AnyCancellable?
    var panelText: String { summary.text }
    var panelStatus: String { latestPage?.blocks.isEmpty == false ? summary.status : status }
    @Published private(set) var panelVisible = false
    @Published var positionLocked = false
    @Published var background = (UserDefaults.standard.data(forKey: "summaryBackground").flatMap { try? JSONDecoder().decode(CaptionRGB.self, from: $0) }) ?? .forest {
        didSet { if let data = try? JSONEncoder().encode(background) { UserDefaults.standard.set(data, forKey: "summaryBackground") } }
    }
    @Published var opacity = UserDefaults.standard.object(forKey: "summaryOpacity") == nil ? 0.9 : clamp(UserDefaults.standard.double(forKey: "summaryOpacity"), 0, 1) {
        didSet { UserDefaults.standard.set(opacity, forKey: "summaryOpacity") }
    }
    var foreground: Color { background.isLight ? Color(white: 0.08) : .white }
    @Published var fontSize = UserDefaults.standard.object(forKey: "slideTranslationFontSize") == nil ? 14.0 : clamp(UserDefaults.standard.double(forKey: "slideTranslationFontSize"), 12, 32) {
        didSet { UserDefaults.standard.set(fontSize, forKey: "slideTranslationFontSize") }
    }
    @Published private(set) var source: CaptionLanguage = .japanese
    @Published private(set) var target: CaptionLanguage = .english
    @Published private(set) var regions: [CGRect] = []
    @Published private(set) var isEditingRegions = false
    private var regionEditor: SlideRegionSelectionController?
    private var openEditorOnFrame = false
    var canEditRegions: Bool { isRunning && lastFrame != nil }
    private let capture = SlideCapture()
    private var translationPanel: SlideTranslationPanelController?
    private var demo: SlideDemoController?
    private var analysis: SlideAnalysis?
    private var frame = CGRect.zero
    private var captureSize: CGSize?
    private var lastSignature = ""
    private var generation = 0
    private var captureGeneration = 0
    private var analysisTask: Task<Void, Never>?
    private var settleTask: Task<Void, Never>?
    private var pendingFrame: SlideFrame?
    private var lastFrame: SlideFrame?
    private var latestPage: SlidePage?

    init() {
        summarySubscription = summary.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        capture.onSelection = { [weak self] name in
            guard let self else { return }
            self.captureGeneration += 1; self.captureSize = nil; self.lastSignature = ""
            self.analysisTask?.cancel(); self.analysisTask = nil; self.pendingFrame = nil; self.lastFrame = nil
            self.regionEditor?.dismiss(); self.regionEditor = nil; self.isEditingRegions = false
            self.regions = []; self.openEditorOnFrame = true
            self.clearPage(); self.isSelecting = false; self.isRunning = true; self.selectedName = name
            self.status = "選んだ画面を読み込んでいます。プレビューが開いたら、資料の部分をドラッグしてください。"

        }
        capture.onFrame = { [weak self] frame in self?.receive(frame) }
        capture.onStopped = { [weak self] message in self?.stop(); self?.status = message }
        capture.onCancelled = { [weak self] in self?.isSelecting = false }
        capture.onUnavailable = { [weak self] in
            guard let self, self.isRunning else { return }
            self.captureGeneration += 1; self.analysisTask?.cancel(); self.analysisTask = nil; self.pendingFrame = nil
            self.lastSignature = ""; self.clearPage()
            self.status = "選択した画面の表示を待っています…"
        }
    }
    func configure(source: CaptionLanguage, target: CaptionLanguage) {
        guard source != self.source || target != self.target else { return }
        let wasVisible = translationPanel?.panel.isVisible == true
        stop()
        self.source = source; self.target = target
        status = "言語を変更しました。画面を選ぶと \(target.name) で要約を表示します。"
        if wasVisible { showTranslationPanel() }
    }
    func chooseScreen() {
        if isDemo { stop() }
        isSelecting = true
        capture.select()
    }
    func showDemo() {
        stop(); isDemo = true; isRunning = true; openEditorOnFrame = true; selectedName = "要約デモ（サンプル資料）"
        let controller = SlideDemoController(language: source)
        demo = controller
        controller.onFrame = { [weak self] image, appFrame in
            let primary = NSScreen.screens.first?.frame.height ?? 900
            let quartz = CGRect(x: appFrame.minX, y: primary - appFrame.maxY, width: appFrame.width, height: appFrame.height)
            self?.receive(SlideFrame(image: image, quartzFrame: quartz, isWindow: true))
        }
        controller.onClose = { [weak self] in if self?.isDemo == true { self?.stop() } }
        controller.show()
    }
    func stop() {
        captureGeneration += 1; capture.stop(); isRunning = false; isSelecting = false; isDemo = false
        regionEditor?.dismiss(); regionEditor = nil; isEditingRegions = false; openEditorOnFrame = false; regions = []
        analysisTask?.cancel(); analysisTask = nil; pendingFrame = nil; lastFrame = nil; captureSize = nil
        clearPage(); lastSignature = ""; demo?.close(); demo = nil
        hideTranslationPanel()
        selectedName = "画面は未選択"; status = "資料の要約を停止しました。"
    }
    func refresh() {
        guard isRunning else { return }
        captureGeneration += 1; analysisTask?.cancel(); analysisTask = nil; pendingFrame = nil
        lastSignature = ""; clearPage()
        if let lastFrame { receive(lastFrame) }
    }
    func resummarize() { summary.invalidateCache(); refresh() }
    func setGlossary(_ glossary: MaterialGlossary?) { summary.setGlossary(glossary, sourceLanguage: source) }
    private func updateSummary() {
        summary.setSourceLanguage(source)
        summary.update(source: latestPage?.blocks.map(\.text).joined(separator: "\n\n") ?? "", target: target, active: isRunning)
    }
    func showTranslationPanel() {
        if translationPanel == nil { translationPanel = SlideTranslationPanelController(model: self) }
        panelVisible = true
        translationPanel?.show(near: frame)
    }
    func hideTranslationPanel() { panelVisible = false; translationPanel?.hide() }
    func togglePanel() { if panelVisible { hideTranslationPanel() } else { showTranslationPanel() } }
    func resetPanelPosition() {
        if translationPanel == nil { translationPanel = SlideTranslationPanelController(model: self) }
        translationPanel?.resetPosition(near: frame)
        showTranslationPanel()
    }
    func editRegions() {
        if isEditingRegions { regionEditor?.show(); return }
        guard let incoming = lastFrame, isRunning, !isEditingRegions else { return }
        captureGeneration += 1; analysisTask?.cancel(); analysisTask = nil; pendingFrame = nil
        clearPage(); lastSignature = ""; isEditingRegions = true; openEditorOnFrame = false
        status = "資料の部分をドラッグして囲んでください。選んだ範囲の文字だけを要約します。"
        let editor = SlideRegionSelectionController(image: incoming.image, regions: regions)
        regionEditor = editor
        editor.completion = { [weak self] selected in
            guard let self else { return }
            self.isEditingRegions = false; self.regionEditor = nil
            if let selected { self.regions = selected }
            if self.regions.isEmpty { self.status = "「範囲を指定」で資料の部分を囲むと、要約を開始します。" }
            else { self.refresh(); self.showTranslationPanel() }
        }
        hideTranslationPanel(); editor.show()
    }
    private func clearPage() {
        generation += 1; settleTask?.cancel(); settleTask = nil; latestPage = nil
        analysis = nil; pageRevision += 1
        summary.clear()
    }
    private func receive(_ incoming: SlideFrame) {
        guard isRunning, incoming.quartzFrame.width > 0, incoming.quartzFrame.height > 0 else { return }
        if let size = captureSize, !isDemo, abs(size.width - incoming.quartzFrame.width) > 2 || abs(size.height - incoming.quartzFrame.height) > 2 {
            captureGeneration += 1; analysisTask?.cancel(); analysisTask = nil; pendingFrame = nil
            lastSignature = ""; clearPage()
        }
        captureSize = incoming.quartzFrame.size
        lastFrame = incoming
        guard !isEditingRegions else { return }
        guard !regions.isEmpty else {
            if openEditorOnFrame { editRegions() }
            return
        }
        pendingFrame = incoming
        guard analysisTask == nil else { return }
        analyzePending()
    }
    private func analyzePending() {
        guard let incoming = pendingFrame, isRunning, !isEditingRegions, !regions.isEmpty else { return }
        pendingFrame = nil
        let token = captureGeneration
        let newFrame = SlideCoordinates.appKitFrame(quartz: incoming.quartzFrame, primaryHeight: NSScreen.screens.first?.frame.height ?? 900)
        let ownWindows = NSApp.windows.filter { $0.isVisible && $0 !== demo?.window }
        let protected = ownWindows.map { SlideCoordinates.localRect(appKit: $0.frame, contentFrame: newFrame) }.filter { $0.intersects(CGRect(origin: .zero, size: newFrame.size)) }
        let ignored = isDemo || incoming.isWindow ? [] : protected
        let language = source
        let selectedRegions = regions
        analysisTask = Task { [weak self] in
            do {
                // Detect columns when present; fall back to rows. The UI needs no reading-order setting.
                let result = try await Task.detached(priority: .userInitiated) { try SlideAnalyzer.analyze(image: incoming.image, size: newFrame.size, language: language, ignored: ignored, regions: selectedRegions, order: .columns, buildOccupancy: false) }.value
                guard let self, !Task.isCancelled, token == self.captureGeneration, self.isRunning else { return }
                self.frame = newFrame
                let signature = result.signature
                if signature != self.lastSignature {
                    self.lastSignature = signature; self.clearPage(); self.analysis = result
                    self.status = result.blocks.isEmpty ? "選択した画面に \(self.source.name) の文字が見つかりません。" : "\(result.blocks.count)か所の文章を読み取りました。要約を準備しています…"
                    let version = self.generation
                    self.settleTask = Task { [weak self] in
                        try? await Task.sleep(for: .milliseconds(350))
                        guard !Task.isCancelled, let self, self.generation == version, self.isRunning else { return }
                        let page = SlidePage(blocks: result.blocks)
                        self.latestPage = page
                        self.updateSummary()

                    }
                } else {
                    self.analysis = result
                }
                self.analysisTask = nil
                self.analyzePending()
            } catch {
                guard let self, token == self.captureGeneration, !Task.isCancelled else { return }
                self.analysisTask = nil; self.clearPage(); self.status = "画面の文字を読み取れませんでした。「要約し直す」で再試行できます。"
                self.analyzePending()
            }
        }
    }
    func shutdown() { stop(); translationPanel = nil }
}
