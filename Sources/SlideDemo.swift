import AppKit

@MainActor
final class SlideDemoController: NSObject, NSWindowDelegate {
    let window: NSWindow
    private let canvas: SlideDemoCanvas
    var onFrame: ((CGImage, CGRect) -> Void)?
    var onClose: (() -> Void)?
    init(language: CaptionLanguage) {
        let available = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let width = min(1000, available.width - 60), height = min(650, available.height - 90)
        canvas = SlideDemoCanvas(frame: CGRect(x: 0, y: 0, width: width, height: height), language: language)
        window = NSWindow(contentRect: canvas.bounds, styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        super.init()
        window.title = "パネルデモ — スライドをクリックすると次へ"
        window.contentView = canvas; window.isReleasedWhenClosed = false; window.delegate = self
        window.center()
        canvas.onChange = { [weak self] in self?.emit() }
    }
    func show() { window.makeKeyAndOrderFront(nil); emit() }
    func close() { window.close() }
    func showAnnotations(_ annotations: [SlideAnnotation], fontSize: Double) {
        canvas.annotations = annotations; canvas.annotationFontSize = fontSize; canvas.needsDisplay = true
    }
    func windowWillClose(_ notification: Notification) { onClose?() }
    func windowDidMove(_ notification: Notification) { emit() }
    private func emit() {
        canvas.capturingSource = true
        defer { canvas.capturingSource = false; canvas.needsDisplay = true }
        canvas.needsDisplay = true
        canvas.displayIfNeeded()
        guard let rep = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds) else { return }
        canvas.cacheDisplay(in: canvas.bounds, to: rep)
        guard let image = rep.cgImage else { return }
        onFrame?(image, window.convertToScreen(canvas.convert(canvas.bounds, to: nil)))
    }
}

final class SlideDemoCanvas: NSView {
    let language: CaptionLanguage
    var page = 0
    var annotations: [SlideAnnotation] = []
    var annotationFontSize = 14.0
    var capturingSource = false
    var onChange: (() -> Void)?
    override var isFlipped: Bool { true }
    init(frame: CGRect, language: CaptionLanguage) { self.language = language; super.init(frame: frame) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func mouseDown(with event: NSEvent) { page = (page + 1) % 2; needsDisplay = true; onChange?() }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { "パネルデモ・スライド\(page + 1)。押すと次のスライド" }
    override func accessibilityValue() -> Any? { annotations.map(\.text).joined(separator: "\n") }
    override func accessibilityPerformPress() -> Bool { page = (page + 1) % 2; needsDisplay = true; onChange?(); return true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill(); bounds.fill()
        let scale = bounds.width / 1000
        func text(_ value: String, x: Double, y: Double, width: Double, size: Double, bold: Bool = false) {
            (value as NSString).draw(in: CGRect(x: x * scale, y: y * scale, width: width * scale, height: 100 * scale), withAttributes: [.font: NSFont.systemFont(ofSize: size * scale, weight: bold ? .semibold : .regular), .foregroundColor: NSColor(calibratedWhite: 0.1, alpha: 1)])
        }
        let headings: [CaptionLanguage: [String]] = [.japanese: ["情報の流れを見てみよう", "アイデアを形にする"], .english: ["How information flows", "Turn ideas into prototypes"], .chinese: ["观察信息的流动", "把想法变成原型"], .traditionalChinese: ["觀察資訊的流動", "把想法變成原型"]]
        let first: [CaptionLanguage: [String]] = [.japanese: ["入力した情報を、コンピュータが処理します。", "まず、身近な道具の使いにくさを見つけます。"], .english: ["A computer processes the information we enter.", "First, find a problem with an everyday tool."], .chinese: ["计算机处理我们输入的信息。", "首先，找到日常工具中不方便的地方。"], .traditionalChinese: ["電腦處理我們輸入的資訊。", "首先，找到日常工具中不方便的地方。"]]
        let second: [CaptionLanguage: [String]] = [.japanese: ["処理した結果は、画面や音で伝えられます。", "簡単な試作品を作り、使いながら改善します。"], .english: ["The results appear as images or sounds.", "Build a simple prototype and improve it through use."], .chinese: ["处理结果通过画面或声音传达。", "制作简单的原型，在使用中改进。"], .traditionalChinese: ["處理結果透過畫面或聲音傳達。", "製作簡單的原型，在使用中改進。"]]
        text(headings[language]![page], x: 55, y: 50, width: 880, size: 34, bold: true)
        text(first[language]![page], x: 55, y: 190, width: 570, size: 24)
        text(second[language]![page], x: 55, y: 380, width: 570, size: 24)
        NSColor(calibratedRed: 0.78, green: 0.88, blue: 0.83, alpha: 1).setFill()
        let figure = CGRect(x: 710 * scale, y: 180 * scale, width: 220 * scale, height: 300 * scale)
        NSBezierPath(roundedRect: figure, xRadius: 18, yRadius: 18).fill()
        NSColor(calibratedRed: 0.19, green: 0.38, blue: 0.30, alpha: 1).setFill()
        NSBezierPath(ovalIn: CGRect(x: 755 * scale, y: 215 * scale, width: 130 * scale, height: 130 * scale)).fill()
        CGRect(x: 775 * scale, y: 375 * scale, width: 90 * scale, height: 65 * scale).fill()
        text("\(page + 1) / 2", x: 880, y: 570, width: 80, size: 16)
        if !capturingSource { SlideAnnotationRenderer.draw(annotations, fontSize: annotationFontSize) }
    }
}
