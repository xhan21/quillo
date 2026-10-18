import AppKit

@MainActor
final class SlideOverlay {
    let panel: CaptionPanel
    private let canvas = SlideAnnotationCanvas()
    init() {
        panel = CaptionPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Quillo — 資料の翻訳"
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = false
        panel.level = .statusBar; panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = canvas
    }
    func show(_ annotations: [SlideAnnotation], frame: CGRect, fontSize: Double) {
        canvas.annotations = annotations; canvas.fontSize = fontSize
        panel.setFrame(frame, display: true); canvas.needsDisplay = true
        if annotations.isEmpty { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
    }
    func hide() { panel.orderOut(nil) }
}

private final class SlideAnnotationCanvas: NSView {
    var annotations: [SlideAnnotation] = []
    var fontSize = 14.0
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        SlideAnnotationRenderer.draw(annotations, fontSize: fontSize)
    }
    override func accessibilityLabel() -> String? { "資料の翻訳：" + annotations.map(\.text).joined(separator: "。") }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .staticText }
    override func accessibilityValue() -> Any? { annotations.map(\.text).joined(separator: "\n") }
}
