import AppKit
import SwiftUI
import Combine

final class SummaryPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class SummaryDragSurface: NSView {
    private var startFrame = CGRect.zero
    private var startPoint = CGPoint.zero
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        startFrame = window.frame; startPoint = window.convertPoint(toScreen: event.locationInWindow)
    }
    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let point = window.convertPoint(toScreen: event.locationInWindow)
        window.setFrameOrigin(CGPoint(x: startFrame.minX + point.x - startPoint.x, y: startFrame.minY + point.y - startPoint.y))
    }
}

@MainActor
final class SlideTranslationPanelController: NSObject, NSWindowDelegate {
    let panel: SummaryPanel
    let presentation = SlidePanelPresentation()
    private weak var model: SlideTranslationModel?
    private var subscription: AnyCancellable?
    private var resizeGrip: CaptionResizeGrip!
    private var hasPosition = false
    init(model: SlideTranslationModel) {
        self.model = model
        panel = SummaryPanel(contentRect: CGRect(x: 0, y: 0, width: 520, height: 260), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.title = "Quillo — 資料の要約"
        presentation.automatic = false
        panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = false
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isMovableByWindowBackground = false; panel.delegate = self
        let container = NSView(frame: panel.frame)
        let host = NSHostingView(rootView: SlideTranslationPanelView(model: model, presentation: presentation))
        host.sizingOptions = []; host.frame = container.bounds; host.autoresizingMask = [.width, .height]
        container.addSubview(host)
        let dragSurface = SummaryDragSurface(frame: container.bounds)
        dragSurface.autoresizingMask = [.width, .height]
        dragSurface.setAccessibilityElement(false)
        container.addSubview(dragSurface)
        resizeGrip = CaptionResizeGrip(frame: CGRect(x: container.bounds.width - 32, y: 6, width: 26, height: 26))
        resizeGrip.autoresizingMask = [.minXMargin, .maxYMargin]
        resizeGrip.toolTip = "ドラッグで幅と高さを変更"
        resizeGrip.onResize = { [weak self] start, delta in self?.resize(from: start, delta: delta) }
        container.addSubview(resizeGrip); panel.contentView = container
        if let saved = UserDefaults.standard.string(forKey: "summaryOverlayFrame") {
            let rect = NSRectFromString(saved)
            if rect.width >= 320, rect.height >= 160, NSScreen.screens.contains(where: { $0.visibleFrame.intersection(rect).width > 100 && $0.visibleFrame.intersection(rect).height > 100 }) {
                panel.setFrame(rect, display: false); hasPosition = true
            }
        }
        subscription = model.objectWillChange.sink { [weak self] _ in DispatchQueue.main.async { self?.update() } }
    }
    func resetPosition(near sourceFrame: CGRect) { hasPosition = false; place(near: sourceFrame); saveFrame() }
    private func place(near sourceFrame: CGRect) {
        guard !hasPosition else { return }
        let available = NSScreen.screens.max { a, b in
            let aa = a.visibleFrame.intersection(sourceFrame), bb = b.visibleFrame.intersection(sourceFrame)
            return (aa.isNull ? 0 : aa.width * aa.height) < (bb.isNull ? 0 : bb.width * bb.height)
        }?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let w = min(520.0, available.width - 24), h = min(260.0, available.height - 30)
        panel.setFrame(CGRect(x: available.maxX - w - 12, y: available.midY - h / 2, width: w, height: h), display: false)
        hasPosition = true
    }
    func show(near sourceFrame: CGRect) { place(near: sourceFrame); update(); panel.makeKeyAndOrderFront(nil) }
    func hide() { panel.orderOut(nil) }
    private func update() {
        guard let model else { return }
        presentation.update(text: model.panelText, revision: model.pageRevision, preferred: model.fontSize)
        panel.ignoresMouseEvents = model.positionLocked
        resizeGrip.isHidden = model.positionLocked
        resizeGrip.ink = NSColor(model.foreground).withAlphaComponent(0.55)
    }
    private func resize(from start: CGRect, delta: CGSize) {
        guard model?.positionLocked == false, let screen = panel.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let width = clamp(start.width + delta.width, 320, max(320, visible.width - 24))
        let height = clamp(start.height - delta.height, 160, max(160, visible.height - 24))
        panel.setFrame(CGRect(x: clamp(start.minX, visible.minX, visible.maxX - width), y: clamp(start.maxY - height, visible.minY, visible.maxY - height), width: width, height: height), display: true)
        saveFrame()
    }
    func windowDidMove(_ notification: Notification) { saveFrame() }
    func windowDidResize(_ notification: Notification) { saveFrame() }
    private func saveFrame() { UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: "summaryOverlayFrame") }
}

private struct SlideTranslationPanelView: View {
    @ObservedObject var model: SlideTranslationModel
    @ObservedObject var presentation: SlidePanelPresentation
    private var title: String {
        let translated = model.source != model.target
        switch model.target {
        case .japanese: return translated ? "スライド要約・翻訳" : "スライド要約"
        case .english: return translated ? "Translated slide summary" : "Slide summary"
        case .chinese: return translated ? "幻灯片摘要翻译" : "幻灯片摘要"
        case .traditionalChinese: return translated ? "投影片摘要翻譯" : "投影片摘要"
        }
    }
    private var placeholder: String {
        if model.summary.busy {
            switch model.target {
            case .japanese: return "要約しています…"
            case .english: return "Summarizing…"
            case .chinese: return "正在整理要点…"
            case .traditionalChinese: return "正在整理重點…"
            }
        }
        switch model.target {
        case .japanese: return "資料の要約を待っています。"
        case .english: return "Waiting for a slide summary."
        case .chinese: return "等待资料摘要。"
        case .traditionalChinese: return "等待資料摘要。"
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Label(title, systemImage: "doc.text")
                    .font(.system(size: 18, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Text(model.target.name).font(.system(size: 10, weight: .medium)).padding(.top, 5).foregroundStyle(model.foreground.opacity(0.65))
            }.foregroundStyle(model.foreground).allowsHitTesting(false)
            GeometryReader { geometry in
                SlidePanelTextView(text: presentation.layout.pages.count <= 1 ? presentation.currentText : "", fontSize: presentation.layout.fontSize, foreground: NSColor(model.foreground))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onAppear { resize(geometry.size) }
                    .onChange(of: geometry.size) { _, size in resize(size) }
                if model.panelText.isEmpty {
                    Text(placeholder).font(.system(size: 13)).foregroundStyle(model.foreground.opacity(0.7)).fixedSize(horizontal: false, vertical: true).allowsHitTesting(false)
                }
            }
        }.padding(23)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(model.background.color.opacity(model.opacity))
        .clipShape(RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(model.foreground.opacity(model.positionLocked ? 0 : 0.25), lineWidth: 1))
        .padding(3)
        .accessibilityElement(children: .contain).accessibilityLabel("資料の要約パネル")
    }
    private func resize(_ size: CGSize) {
        // Clear / shorten the summary before reflowing, so no first page of a longer summary is shown.
        model.summary.resize(size); presentation.resize(size)
    }
}

private struct SlidePanelTextView: NSViewRepresentable {
    var text: String
    var fontSize: Double
    var foreground: NSColor
    func makeNSView(context: Context) -> NSTextView {
        let view = NSTextView()
        view.isEditable = false; view.isSelectable = false; view.drawsBackground = false
        view.textContainerInset = .zero; view.textContainer?.lineFragmentPadding = 0
        view.isVerticallyResizable = false; view.isHorizontallyResizable = false
        view.textContainer?.widthTracksTextView = true
        view.setAccessibilityLabel("資料の要約")
        return view
    }
    func updateNSView(_ view: NSTextView, context: Context) {
        var attributes = SlidePanelTypesetting.attributes(fontSize: fontSize)
        attributes[.foregroundColor] = foreground
        let value = NSAttributedString(string: text, attributes: attributes)
        if view.attributedString() != value { view.textStorage?.setAttributedString(value) }
    }
}
