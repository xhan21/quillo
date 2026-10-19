import AppKit

@main enum SlideRegionEditingTests {
    static func close(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) + abs(a.minY - b.minY) + abs(a.width - b.width) + abs(a.height - b.height) < 0.000001
    }
    @MainActor static func main() {
        _ = NSApplication.shared
        let bounds = CGRect(x: 20, y: 80, width: 1000, height: 600)
        let original = CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
        let absolute = SlideRegionGeometry.absolute(original, in: bounds)
        let center = CGPoint(x: absolute.midX, y: absolute.midY)
        var editor = SlideRegionEditing(regions: [original])
        editor.begin(at: center, in: bounds); editor.end(at: center)
        precondition(!editor.canUndo && editor.regions == [original], "A click only selects the existing region")
        editor.begin(at: center, in: bounds)
        editor.update(to: CGPoint(x: center.x + 100, y: center.y + 60))
        precondition(editor.regions == [original], "Dragging previews do not change the accepted crop")
        editor.end(at: CGPoint(x: center.x + 100, y: center.y + 60))
        precondition(editor.regions.count == 1 && close(editor.regions[0], CGRect(x: 0.2, y: 0.3, width: 0.3, height: 0.4)))
        editor.undo(); precondition(editor.regions == [original] && !editor.canUndo)
        // Moving beyond any image edge preserves size and clips position.
        for point in [CGPoint(x: -900, y: -900), CGPoint(x: 9000, y: 9000)] {
            editor.begin(at: center, in: bounds); editor.end(at: point)
            let rect = editor.regions[0]
            precondition(abs(rect.width - original.width) < 0.000001 && abs(rect.height - original.height) < 0.000001)
            precondition(rect.minX >= 0 && rect.minY >= 0 && rect.maxX <= 1.000001 && rect.maxY <= 1.000001)
            editor.undo()
        }
        for handle in SlideRegionHandle.allCases {
            var resized = SlideRegionEditing(regions: [original])
            let start = handle.point(in: absolute)
            guard case .resize(0, let hit) = resized.hit(at: start, in: bounds) else { fatalError("Handle must resize") }
            precondition(hit == handle)
            let point = CGPoint(x: start.x + (handle.adjustsLeft ? -50 : handle.adjustsRight ? 50 : 0),
                                y: start.y + (handle.adjustsTop ? -30 : handle.adjustsBottom ? 30 : 0))
            resized.begin(at: start, in: bounds); resized.end(at: point)
            let result = resized.regions[0]
            precondition(abs(result.minX - (original.minX - (handle.adjustsLeft ? 0.05 : 0))) < 0.000001)
            precondition(abs(result.minY - (original.minY - (handle.adjustsTop ? 0.05 : 0))) < 0.000001)
            precondition(abs(result.width - (original.width + (handle.adjustsLeft || handle.adjustsRight ? 0.05 : 0))) < 0.000001)
            precondition(abs(result.height - (original.height + (handle.adjustsTop || handle.adjustsBottom ? 0.05 : 0))) < 0.000001)
            resized.undo(); precondition(resized.regions == [original])
            resized.begin(at: start, in: bounds)
            resized.end(at: CGPoint(x: handle.adjustsLeft ? 9999 : -9999, y: handle.adjustsTop ? 9999 : -9999))
            precondition(resized.regions[0].width * bounds.width >= 11.999 && resized.regions[0].height * bounds.height >= 11.999, "Crossing opposite edge keeps a usable crop")
        }
        let other = CGRect(x: 0.65, y: 0.2, width: 0.25, height: 0.4)
        editor = SlideRegionEditing(regions: [original, other])
        editor.begin(at: center, in: bounds); editor.end(at: CGPoint(x: center.x + 550, y: center.y))
        precondition(editor.regions == [original, other] && editor.notice != nil && !editor.canUndo, "Reject overlapping moves without losing either region")
        let edge = SlideRegionHandle.right.point(in: absolute)
        editor.begin(at: edge, in: bounds); editor.end(at: CGPoint(x: edge.x + 400, y: edge.y))
        precondition(editor.regions == [original, other] && editor.notice != nil, "Reject overlapping resize")
        editor.begin(at: center, in: bounds); editor.end(at: center)
        editor.deleteSelected(); precondition(editor.regions == [other], "Delete the selected region, not the last one")
        editor.undo(); precondition(editor.regions == [original, other] && editor.selected == 0)
        editor.clear(); precondition(editor.regions.isEmpty)
        editor.undo(); precondition(editor.regions == [original, other])
        editor.begin(at: center, in: bounds); editor.update(to: CGPoint(x: 50, y: 100)); editor.cancelDrag()
        precondition(editor.regions == [original, other] && !editor.isDragging && !editor.canUndo)
        // Reverse-direction creation, clipped to image; repeated edits undo separately.
        editor = SlideRegionEditing(regions: [])
        editor.begin(at: CGPoint(x: 600, y: 400), in: bounds); editor.end(at: CGPoint(x: -100, y: -100))
        precondition(close(editor.regions[0], CGRect(x: 0, y: 0, width: 0.58, height: 320.0 / 600)))
        editor.clear(); editor.undo(); precondition(editor.regions.count == 1)
        editor.undo(); precondition(editor.regions.isEmpty && !editor.canUndo)
        editor.begin(at: CGPoint(x: 30, y: 90), in: bounds); editor.end(at: CGPoint(x: 33, y: 93))
        precondition(editor.regions.isEmpty && !editor.canUndo, "Tiny clicks do not create crops")
        // Normalized regions map to the same image after resizing the preview.
        let resizedBounds = CGRect(x: 0, y: 170, width: 500, height: 300)
        let scaled = SlideRegionGeometry.absolute(original, in: resizedBounds)
        editor = SlideRegionEditing(regions: [original])
        editor.begin(at: CGPoint(x: scaled.midX, y: scaled.midY), in: resizedBounds)
        editor.end(at: CGPoint(x: scaled.midX + 50, y: scaled.midY + 30))
        precondition(close(editor.regions[0], CGRect(x: 0.2, y: 0.3, width: 0.3, height: 0.4)))

        // AppKit event forwarding uses a letterboxed image and top-left coordinates.
        let context = CGContext(data: nil, width: 1000, height: 600, bitsPerComponent: 8, bytesPerRow: 4000, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let image = context.makeImage()!
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 500, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
        let canvas = SlideRegionCanvas(frame: CGRect(x: 0, y: 0, width: 500, height: 500), image: image, regions: [original])
        window.contentView = canvas
        func event(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        // Image bounds are (0,100,500,300), so the crop center is (125,220).
        canvas.mouseDown(with: event(.leftMouseDown, CGPoint(x: 125, y: 220)))
        canvas.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: 175, y: 250)))
        canvas.mouseUp(with: event(.leftMouseUp, CGPoint(x: 175, y: 250)))
        precondition(close(canvas.regions[0], CGRect(x: 0.2, y: 0.3, width: 0.3, height: 0.4)), "Canvas must forward flipped/letterboxed drag positions")
        canvas.undoEdit(); precondition(canvas.regions == [original])
        let controller = SlideRegionSelectionController(image: image, regions: [original])
        var completed = false
        controller.completion = { result in precondition(result == nil); completed = true }
        controller.window.performClose(nil)
        precondition(completed, "Closing the editor cancels without publishing changes")
        let applied = SlideRegionSelectionController(image: image, regions: [original])
        applied.completion = { result in precondition(result == [original]); completed = false }
        let apply = applied.window.contentView!.subviews.compactMap { $0 as? NSButton }.first { $0.title == "この範囲で要約" }!
        apply.performClick(nil); precondition(!completed, "Apply publishes selected regions")
        print("PASS: region move, 8 resize handles, image boundaries, overlap rollback, selected deletion, undo, cancellation, preview resize, AppKit drag and apply")
    }
}
