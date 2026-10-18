import AppKit

// A synthetic drawing of the production layout, not a desktop capture.
@main enum SlideExteriorPreview {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let size = CGSize(width: 1440, height: 880)
        let sourceFrame = CGRect(x: 360, y: 210, width: 720, height: 460)
        var source = SlideOccupancy(size: sourceFrame.size)
        source.mark(CGRect(origin: .zero, size: sourceFrame.size))
        let items: [SlideTranslation] = (0..<16).map { i in
            let rect = CGRect(x: Double(35 + (i % 2) * 350), y: Double(20 + (i / 2) * 52), width: 300, height: 22)
            return .init(id: i, source: .init(id: i, text: "文章 \(i + 1) の内容を説明します。", rect: rect), text: "\(i + 1). The translated paragraph appears outside the material window.")
        }
        let space = SlidePlacementSpace(source: source, sourceFrame: sourceFrame, availableFrame: CGRect(origin: .zero, size: size))
        let result = SlidePlacement.annotations(for: space.translations(items), occupancy: space.occupancy, fontSize: 14, sourceBounds: space.sourceRect)
        let view = ExteriorPreviewCanvas(frame: CGRect(origin: .zero, size: size))
        view.sourceRect = space.sourceRect; view.items = space.translations(items); view.annotations = result.placed
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep)
        let destination = CommandLine.arguments[1]
        try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: destination))
        print("Rendered synthetic layout: \(result.placed.count) external cards, \(result.overflow.count) overflow")
    }
}

private final class ExteriorPreviewCanvas: NSView {
    var sourceRect = CGRect.zero
    var items: [SlideTranslation] = []
    var annotations: [SlideAnnotation] = []
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.91, alpha: 1).setFill(); bounds.fill()
        NSColor.white.setFill(); NSBezierPath(roundedRect: sourceRect, xRadius: 8, yRadius: 8).fill()
        for item in items {
            (item.source.text as NSString).draw(in: item.source.rect, withAttributes: [.font: NSFont.systemFont(ofSize: 16), .foregroundColor: NSColor.black])
        }
        SlideAnnotationRenderer.draw(annotations, fontSize: 14)
    }
}
