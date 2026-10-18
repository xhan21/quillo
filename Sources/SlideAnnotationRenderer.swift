import AppKit

enum SlideAnnotationRenderer {
    static func draw(_ annotations: [SlideAnnotation], fontSize: Double) {
        for annotation in annotations {
            guard let source = annotation.sourceRect else { continue }
            let card = annotation.rect
            let end = CGPoint(x: clamp(source.midX, card.minX, card.maxX), y: clamp(source.midY, card.minY, card.maxY))
            let start = CGPoint(x: clamp(end.x, source.minX, source.maxX), y: clamp(end.y, source.minY, source.maxY))
            let color = NSColor(calibratedRed: 0.16, green: 0.38, blue: 0.31, alpha: 0.65)
            color.setStroke(); color.setFill()
            let line = NSBezierPath(); line.move(to: start); line.line(to: end); line.lineWidth = 1; line.stroke()
            NSBezierPath(ovalIn: CGRect(x: start.x - 2, y: start.y - 2, width: 4, height: 4)).fill()
        }
        for annotation in annotations {
            let rect = annotation.rect
            NSColor(calibratedWhite: 1, alpha: 0.96).setFill()
            let path = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5); path.fill()
            NSColor(calibratedRed: 0.16, green: 0.38, blue: 0.31, alpha: 0.45).setStroke()
            path.lineWidth = 0.7; path.stroke()
            let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 3
            (annotation.text as NSString).draw(in: rect.insetBy(dx: 9, dy: 7), withAttributes: [.font: NSFont.systemFont(ofSize: fontSize), .foregroundColor: NSColor(calibratedRed: 0.10, green: 0.25, blue: 0.20, alpha: 1), .paragraphStyle: paragraph])
        }
    }
}
