import AppKit

// Uses a generated slide only. No screen capture, microphone, or translation.
@main enum SlideRegionPreview {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = PreviewDelegate()
        app.delegate = delegate; app.setActivationPolicy(.regular); app.run()
    }
}
@MainActor private final class PreviewDelegate: NSObject, NSApplicationDelegate {
    private var editor: SlideRegionSelectionController?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let canvas = SlideDemoCanvas(frame: CGRect(x: 0, y: 0, width: 1000, height: 650), language: .japanese)
        let bitmap = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds)!
        canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
        let editor = SlideRegionSelectionController(image: bitmap.cgImage!, regions: [CGRect(x: 0.04, y: 0.20, width: 0.60, height: 0.28)])
        editor.completion = { _ in NSApp.terminate(nil) }
        self.editor = editor; editor.show()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
