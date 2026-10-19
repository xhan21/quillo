import AppKit

@MainActor
final class SlideRegionSelectionController: NSObject, NSWindowDelegate {
    let window: NSWindow
    private let canvas: SlideRegionCanvas
    private let applyButton = NSButton(title: "この範囲で要約", target: nil, action: nil)
    private var undoButton: NSButton!
    private var deleteButton: NSButton!
    private var clearButton: NSButton!
    private let hint = NSTextField(labelWithString: "")
    var completion: (([CGRect]?) -> Void)?
    init(image: CGImage, regions: [CGRect]) {
        let available = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1200, height: 850)
        let size = CGSize(width: min(1040, available.width - 60), height: min(760, available.height - 90))
        canvas = SlideRegionCanvas(frame: CGRect(x: 16, y: 88, width: size.width - 32, height: size.height - 104), image: image, regions: regions)
        window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        super.init()
        window.title = "要約する範囲 — 移動・サイズ調整"
        window.isReleasedWhenClosed = false; window.delegate = self
        window.minSize = CGSize(width: 650, height: 470)
        let content = NSView(frame: CGRect(origin: .zero, size: size)); window.contentView = content
        canvas.autoresizingMask = [.width, .height]; content.addSubview(canvas)
        hint.frame = CGRect(x: 20, y: 51, width: size.width - 40, height: 34); hint.autoresizingMask = [.width]
        hint.maximumNumberOfLines = 2; hint.lineBreakMode = .byWordWrapping
        hint.font = .systemFont(ofSize: 12); content.addSubview(hint)
        @discardableResult func button(_ title: String, x: CGFloat, width: CGFloat, action: Selector) -> NSButton {
            let button = NSButton(title: title, target: self, action: action)
            button.bezelStyle = .rounded; button.frame = CGRect(x: x, y: 16, width: width, height: 30)
            content.addSubview(button)
            return button
        }
        button("キャンセル", x: 16, width: 90, action: #selector(cancel))
        undoButton = button("元に戻す", x: 112, width: 90, action: #selector(undo))
        deleteButton = button("選んだ枠を削除", x: 208, width: 130, action: #selector(deleteSelected))
        clearButton = button("全部消す", x: 344, width: 84, action: #selector(clear))
        undoButton.keyEquivalent = "z"; undoButton.keyEquivalentModifierMask = .command
        applyButton.target = self; applyButton.action = #selector(apply); applyButton.bezelStyle = .rounded
        applyButton.frame = CGRect(x: size.width - 180, y: 16, width: 160, height: 30)
        applyButton.autoresizingMask = [.minXMargin]; applyButton.keyEquivalent = "\r"; content.addSubview(applyButton)
        canvas.onChange = { [weak self] in self?.update() }
        update(); window.center()
    }
    func show() { window.makeKeyAndOrderFront(nil); window.makeFirstResponder(canvas); NSApp.activate(ignoringOtherApps: true) }
    func dismiss() { completion = nil; window.close() }
    func windowWillClose(_ notification: Notification) { let callback = completion; completion = nil; callback?(nil) }
    private func update() {
        hint.stringValue = canvas.editing.notice ?? "枠の中をドラッグ：移動 ／ 角・辺をドラッグ：サイズ変更\n枠のない場所をドラッグ：追加（\(canvas.regions.count)か所を選択中）"
        applyButton.isEnabled = !canvas.regions.isEmpty && !canvas.editing.isDragging
        undoButton.isEnabled = canvas.editing.canUndo && !canvas.editing.isDragging
        deleteButton.isEnabled = canvas.editing.selected != nil && !canvas.editing.isDragging
        clearButton.isEnabled = !canvas.regions.isEmpty && !canvas.editing.isDragging
    }
    private func finish(_ value: [CGRect]?) { let callback = completion; completion = nil; window.close(); callback?(value) }
    @objc private func apply() { finish(canvas.regions) }
    @objc private func cancel() { finish(nil) }
    @objc private func undo() { canvas.undoEdit() }
    @objc private func deleteSelected() { canvas.deleteSelected() }
    @objc private func clear() { canvas.clear() }
}

final class SlideRegionCanvas: NSView {
    private let image: NSImage
    private(set) var editing: SlideRegionEditing
    var regions: [CGRect] { editing.regions }
    var onChange: (() -> Void)?
    private var tracking: NSTrackingArea?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    init(frame: CGRect, image: CGImage, regions: [CGRect]) {
        self.image = NSImage(cgImage: image, size: CGSize(width: image.width, height: image.height))
        self.editing = SlideRegionEditing(regions: regions)
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private var imageRect: CGRect {
        let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
    }
    private func changed() { needsDisplay = true; window?.invalidateCursorRects(for: self); onChange?() }
    func undoEdit() { editing.undo(); changed() }
    func deleteSelected() { editing.deleteSelected(); changed() }
    func clear() { editing.clear(); changed() }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        editing.begin(at: point, in: imageRect); changed()
        if case .move = editing.hit(at: point, in: imageRect) { NSCursor.closedHand.set() }
    }
    override func mouseDragged(with event: NSEvent) { editing.update(to: convert(event.locationInWindow, from: nil)); changed() }
    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        editing.end(at: point); changed(); cursor(at: point).set()
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 { deleteSelected() }
        else if event.keyCode == 53 && editing.isDragging { editing.cancelDrag(); changed() }
        else { super.keyDown(with: event) }
    }
    override func cancelOperation(_ sender: Any?) {
        if editing.isDragging { editing.cancelDrag(); changed() }
        else { window?.performClose(sender) }
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.16, alpha: 1).setFill(); bounds.fill()
        image.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        let shade = NSBezierPath(rect: imageRect); shade.windingRule = .evenOdd
        var rects = regions.map { SlideRegionGeometry.absolute($0, in: imageRect) }
        if let preview = editing.preview {
            let rect = SlideRegionGeometry.absolute(preview, in: imageRect)
            if let index = editing.editingIndex { rects[index] = rect }
            else { rects.append(rect) }
        }
        // Clip even-odd shading to the image; invalid overlapping previews may
        // overlap temporarily but can never become accepted OCR regions.
        NSGraphicsContext.saveGraphicsState(); NSBezierPath(rect: imageRect).addClip()
        for rect in rects { shade.appendRect(rect) }
        NSColor.black.withAlphaComponent(0.35).setFill(); shade.fill()
        NSGraphicsContext.restoreGraphicsState()
        for (i, rect) in rects.enumerated() {
            let active = i == editing.selected || (editing.isDragging && i == regions.count)
            let invalid = editing.isDragging && !editing.previewIsValid && (i == editing.editingIndex || i == regions.count)
            let color: NSColor = invalid ? .systemRed : .systemMint
            color.setStroke(); let border = NSBezierPath(rect: rect); border.lineWidth = active ? 3 : 1.5; border.stroke()
            let label = CGRect(x: rect.minX + 8, y: rect.minY + 8, width: 26, height: 24)
            NSColor(calibratedRed: 0.10, green: 0.35, blue: 0.27, alpha: 1).setFill(); label.fill()
            ("\(i + 1)" as NSString).draw(at: CGPoint(x: label.minX + 7, y: label.minY + 3), withAttributes: [.font: NSFont.boldSystemFont(ofSize: 13), .foregroundColor: NSColor.white])
            if active {
                for handle in SlideRegionHandle.allCases {
                    let center = handle.point(in: rect)
                    let box = NSBezierPath(rect: CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8))
                    NSColor.white.setFill(); box.fill(); color.setStroke(); box.lineWidth = 1.5; box.stroke()
                }
            }
        }
    }
    private func cursor(at point: CGPoint) -> NSCursor {
        switch editing.hit(at: point, in: imageRect) {
        case .move: return .openHand
        case .resize(_, let handle):
            if handle == .left || handle == .right { return .resizeLeftRight }
            if handle == .top || handle == .bottom { return .resizeUpDown }
            return .crosshair
        case nil: return imageRect.contains(point) ? .crosshair : .arrow
        }
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.cursorUpdate, .mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
    }
    override func cursorUpdate(with event: NSEvent) { cursor(at: convert(event.locationInWindow, from: nil)).set() }
    override func mouseMoved(with event: NSEvent) { cursor(at: convert(event.locationInWindow, from: nil)).set() }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .image }
    override func accessibilityLabel() -> String? { "要約範囲。枠の中をドラッグで移動、角や辺をドラッグでサイズ変更" }
    override func accessibilityValue() -> Any? { "\(regions.count)か所。" + (editing.selected.map { "枠\($0 + 1)を編集中" } ?? "新しい範囲を追加できます") }
}
