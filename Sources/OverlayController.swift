import AppKit
import SwiftUI
import Combine

final class CaptionPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class OverlayController: NSObject, NSWindowDelegate {
    let model: AppModel
    private(set) var panel: CaptionPanel!
    private var subscription: AnyCancellable?
    private var isSizing = false
    private var resizeGrip: CaptionResizeGrip!
    init(model: AppModel) {
        self.model = model
        super.init()
        panel = CaptionPanel(contentRect: NSRect(x: 0, y: 0, width: 900, height: 180), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Quillo — 字幕オーバーレイ"
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        // Keep SwiftUI's ideal size from resizing the borderless panel off-screen.
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 180))
        let hosting = NSHostingView(rootView: OverlayCaptionView(model: model))
        hosting.sizingOptions = []
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        resizeGrip = CaptionResizeGrip(frame: NSRect(x: 868, y: 6, width: 26, height: 26))
        resizeGrip.autoresizingMask = [.minXMargin, .maxYMargin]
        resizeGrip.toolTip = "ドラッグで幅と高さを変更"
        resizeGrip.onResize = { [weak self] start, delta in self?.resize(from: start, delta: delta) }
        container.addSubview(resizeGrip)
        panel.contentView = container
        subscription = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.refreshSize() }
        }
        placeAtBottom()
        if let encoded = UserDefaults.standard.string(forKey: "overlayFrame") {
            let rect = NSRectFromString(encoded)
            if rect.width > 100, NSScreen.screens.contains(where: { $0.visibleFrame.intersects(rect) }) {
                panel.setFrameOrigin(rect.origin)
            }
        }
        refreshSize()
    }
    func show() { refreshSize(); updateInteraction(); panel.orderFrontRegardless() }
    func hide() { panel.orderOut(nil) }
    func updateInteraction() {
        panel.ignoresMouseEvents = model.positionLocked
        panel.isMovableByWindowBackground = !model.positionLocked
        resizeGrip.isHidden = model.positionLocked
    }
    private var selectedScreen: NSScreen {
        let screens = NSScreen.screens
        return screens[min(max(0, model.selectedScreen), screens.count - 1)]
    }
    func moveToSelectedScreen() { placeAtBottom(); model.updateAppearance(); refreshSize(); savePosition() }
    func placeAtBottom() {
        guard !NSScreen.screens.isEmpty else { return }
        let frame = selectedScreen.visibleFrame
        let width = min(model.appearance.width, frame.width - 36)
        panel.setFrame(NSRect(x: frame.midX - width / 2, y: frame.minY + 46, width: width, height: 180), display: true)
    }
    func refreshSize() {
        guard !isSizing, panel != nil, let screen = panel.screen ?? NSScreen.main else { return }
        isSizing = true; defer { isSizing = false }
        let visible = screen.visibleFrame
        let style = model.appearance
        let size = model.captionLayoutSize
        let width = size.width
        let total = size.height
        let old = panel.frame
        let x = clamp(old.origin.x, visible.minX, max(visible.minX, visible.maxX - width))
        let y = clamp(old.origin.y, visible.minY, max(visible.minY, visible.maxY - total))
        panel.setFrame(NSRect(x: x, y: y, width: width, height: total), display: true)
        resizeGrip.ink = NSColor(style.foreground).withAlphaComponent(0.55)
        updateInteraction()
        savePosition()
    }
    private func resize(from start: NSRect, delta: NSSize) {
        guard !model.positionLocked, let screen = panel.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        var style = model.appearance
        style.width = clamp(start.width + delta.width, 320, min(2000, visible.width - 24))
        style.height = clamp(start.height - delta.height, model.minimumPanelHeight, min(900, visible.height - 24))
        style.automaticHeight = false
        model.appearance = style
        model.updateAppearance()
        panel.setFrameOrigin(NSPoint(x: clamp(start.minX, visible.minX, visible.maxX - panel.frame.width), y: clamp(start.maxY - panel.frame.height, visible.minY, visible.maxY - panel.frame.height)))
        savePosition()
    }
    func savePosition() { UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: "overlayFrame") }
    func windowDidMove(_ notification: Notification) { if !isSizing { savePosition() } }
}

final class CaptionResizeGrip: NSView {
    var ink = NSColor.white { didSet { needsDisplay = true } }
    var onResize: ((NSRect, NSSize) -> Void)?
    private var startFrame = NSRect.zero
    private var startPoint = NSPoint.zero
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func draw(_ dirtyRect: NSRect) {
        ink.setStroke()
        let path = NSBezierPath(); path.lineWidth = 1.5
        for offset in [0.0, 5.0, 10.0] {
            path.move(to: NSPoint(x: 7 + offset, y: 7)); path.line(to: NSPoint(x: 21, y: 21 - offset))
        }
        path.stroke()
    }
    override func mouseDown(with event: NSEvent) {
        startFrame = window?.frame ?? .zero
        startPoint = window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
    }
    override func mouseDragged(with event: NSEvent) {
        let point = window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
        onResize?(startFrame, NSSize(width: point.x - startPoint.x, height: point.y - startPoint.y))
    }
}

struct OverlayCaptionView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        let style = model.appearance
        let presentation = model.captionPresentation
        let caption = presentation.caption
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Circle().fill(model.isListening ? Color.red.opacity(0.9) : style.translationForeground).frame(width: 5, height: 5)
                if let state = model.currentCorrectionState {
                    Label(state.label, systemImage: state.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(style.foreground)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(style.foreground.opacity(0.10), in: Capsule())
                        .overlay(Capsule().strokeBorder(style.foreground.opacity(0.25)))
                        .fixedSize().layoutPriority(1)
                        .accessibilityLabel("現在の入力: " + state.label)
                }
                Text(model.captionKind).font(.system(size: 10, weight: .medium))
                Spacer()
                Text(presentation.reading?.continued == true || presentation.sourceReading?.continued == true ? "長文の続き" : model.liveLabel)
                Text(model.historyLabel)
                Text(model.sourceLanguage.name + (model.requiresTranslation ? " → " + model.targetLanguage.name : ""))
            }
            .font(.system(size: 10)).foregroundStyle(style.foreground.opacity(0.60)).lineLimit(1)
            VStack(alignment: .leading, spacing: 9) {
            if let reading = presentation.sourceReading {
                sentenceBlock(reading, color: style.foreground, shadow: style.textShadow)
            }
            if let reading = presentation.reading {
                sentenceBlock(reading, color: style.translationForeground, shadow: style.textShadow)
            }
            if !caption.placeholder.isEmpty {
                Text(caption.placeholder).font(.system(size: min(style.sourceFontSize, style.translationFontSize))).foregroundStyle(style.foreground.opacity(0.65)).fixedSize(horizontal: false, vertical: true)
            }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 23).padding(.vertical, 17)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(style.background.color.opacity(style.opacity))
        .clipShape(RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(style.foreground.opacity(model.positionLocked ? 0 : 0.25), lineWidth: 1))
        .padding(3)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("字幕パネル")
    }
    private func sentenceBlock(_ reading: SentenceCaptionLayout, color: Color, shadow: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(reading.history.enumerated()), id: \.offset) { index, text in
                Text(text).font(.system(size: reading.previousFontSize))
                    .foregroundStyle(color.opacity(index == reading.history.count - 1 ? 0.78 : 0.60))
                    .lineSpacing(5).fixedSize(horizontal: false, vertical: true)
                    .shadow(color: shadow, radius: 1)
                    .accessibilityLabel("\(reading.history.count - index)文前: " + text)
            }
            if !reading.text.isEmpty {
                Text(reading.text).font(.system(size: reading.fontSize)).foregroundStyle(color)
                    .lineSpacing(5).fixedSize(horizontal: false, vertical: true)
                    .shadow(color: shadow, radius: 1)
                    .accessibilityLabel("現在: " + reading.text)
            }
        }
    }
}
