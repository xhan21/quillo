import AppKit

@MainActor
final class SlideRegionSelectionController: NSObject, NSWindowDelegate {
    let window: NSWindow
    private let canvas: SlideRegionCanvas
    private let applyButton = NSButton(title: "この範囲で要約", target: nil, action: nil)
    private let hint = NSTextField(labelWithString: "")
    var completion: (([CGRect]?) -> Void)?
    init(image: CGImage, regions: [CGRect]) {
        let available = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1200, height: 850)
        let size = CGSize(width: min(1040, available.width - 60), height: min(760, available.height - 90))
        canvas = SlideRegionCanvas(frame: CGRect(x: 16, y: 88, width: size.width - 32, height: size.height - 104), image: image, regions: regions)
        window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        super.init()
        window.title = "要約する範囲 — 資料の部分をドラッグ"
        window.isReleasedWhenClosed = false; window.delegate = self
        window.minSize = CGSize(width: 650, height: 470)
        let content = NSView(frame: CGRect(origin: .zero, size: size)); window.contentView = content
        canvas.autoresizingMask = [.width, .height]; content.addSubview(canvas)
        hint.frame = CGRect(x: 20, y: 58, width: size.width - 40, height: 20); hint.autoresizingMask = [.width]
        hint.font = .systemFont(ofSize: 12); content.addSubview(hint)
        func button(_ title: String, x: CGFloat, width: CGFloat, action: Selector) {
            let button = NSButton(title: title, target: self, action: action)
            button.bezelStyle = .rounded; button.frame = CGRect(x: x, y: 16, width: width, height: 30)
            content.addSubview(button)
        }
        button("キャンセル", x: 16, width: 110, action: #selector(cancel))
        button("最後の範囲を削除", x: 135, width: 145, action: #selector(undo))
        button("全部消す", x: 288, width: 100, action: #selector(clear))
        applyButton.target = self; applyButton.action = #selector(apply); applyButton.bezelStyle = .rounded
        applyButton.frame = CGRect(x: size.width - 180, y: 16, width: 160, height: 30)
        applyButton.autoresizingMask = [.minXMargin]; applyButton.keyEquivalent = "\r"; content.addSubview(applyButton)
        canvas.onChange = { [weak self] in self?.update() }
        update(); window.center()
    }
    func show() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    func dismiss() { completion = nil; window.close() }
    func windowWillClose(_ notification: Notification) { let callback = completion; completion = nil; callback?(nil) }
    private func update() {
        hint.stringValue = canvas.notice ?? "\(canvas.regions.count)か所を選択中。複数の範囲を囲めます。選んだ文章の要点を別パネルに表示します。"
        applyButton.isEnabled = !canvas.regions.isEmpty
    }
    private func finish(_ value: [CGRect]?) { let callback = completion; completion = nil; window.close(); callback?(value) }
    @objc private func apply() { finish(canvas.regions) }
    @objc private func cancel() { finish(nil) }
    @objc private func undo() { if !canvas.regions.isEmpty { canvas.regions.removeLast() }; canvas.changed() }
    @objc private func clear() { canvas.regions = []; canvas.changed() }
}

final class SlideRegionCanvas: NSView {
    private let image: NSImage
    var regions: [CGRect]
    var onChange: (() -> Void)?
    var notice: String?
    private var start: CGPoint?
    private var current: CGPoint?
    override var isFlipped: Bool { true }
    init(frame: CGRect, image: CGImage, regions: [CGRect]) {
        self.image = NSImage(cgImage: image, size: CGSize(width: image.width, height: image.height)); self.regions = regions
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private var imageRect: CGRect {
        let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
    }
    func changed() { notice = nil; needsDisplay = true; onChange?() }
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard imageRect.contains(point) else { return }
        start = point; current = point; notice = nil; needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) { guard start != nil else { return }; current = convert(event.locationInWindow, from: nil); needsDisplay = true }
    override func mouseUp(with event: NSEvent) {
        guard let start else { return }
        let point = convert(event.locationInWindow, from: nil)
        let drag = CGRect(x: min(start.x, point.x), y: min(start.y, point.y), width: abs(point.x - start.x), height: abs(point.y - start.y))
        if let rect = SlideRegionGeometry.normalized(drag, in: imageRect) {
            if regions.contains(where: { $0.intersects(rect) }) { notice = "既存の枠と重なっています。不要な枠を削除してから囲み直してください。" }
            else { regions.append(rect) }
        } else { notice = "もう少し大きな範囲をドラッグしてください。" }
        self.start = nil; current = nil; needsDisplay = true; onChange?()
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.16, alpha: 1).setFill(); bounds.fill()
        image.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        let shade = NSBezierPath(rect: imageRect); shade.windingRule = .evenOdd
        var rects = regions.map { SlideRegionGeometry.absolute($0, in: imageRect) }
        if let start, let current { rects.append(CGRect(x: min(start.x, current.x), y: min(start.y, current.y), width: abs(start.x - current.x), height: abs(start.y - current.y)).intersection(imageRect)) }
        for rect in rects { shade.appendRect(rect) }
        NSColor.black.withAlphaComponent(0.35).setFill(); shade.fill()
        for (i, rect) in rects.enumerated() {
            NSColor.systemMint.setStroke(); let border = NSBezierPath(rect: rect); border.lineWidth = 2; border.stroke()
            let label = CGRect(x: rect.minX, y: rect.minY, width: 26, height: 24)
            NSColor(calibratedRed: 0.10, green: 0.35, blue: 0.27, alpha: 1).setFill(); label.fill()
            ("\(i + 1)" as NSString).draw(at: CGPoint(x: label.minX + 7, y: label.minY + 3), withAttributes: [.font: NSFont.boldSystemFont(ofSize: 13), .foregroundColor: NSColor.white])
        }
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .image }
    override func accessibilityLabel() -> String? { "資料の画像。ドラッグして要約範囲を指定" }
    override func accessibilityValue() -> Any? { "\(regions.count)か所を選択中" }
}
