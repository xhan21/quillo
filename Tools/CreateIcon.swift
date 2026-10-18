import AppKit
import Foundation

let output = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let factor = CGFloat(pixels) / 1024
        context.cgContext.scaleBy(x: factor, y: factor)
        NSColor(red: 0.17, green: 0.32, blue: 0.26, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 208, yRadius: 208).fill()
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 600, weight: .bold), .foregroundColor: NSColor(red: 0.85, green: 0.93, blue: 0.68, alpha: 1)]
        let text = "Q" as NSString
        let bounds = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: (1024 - bounds.width) / 2, y: (1024 - bounds.height) / 2 + 24), withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
        let filename = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output).appendingPathComponent(filename))
    }
}
