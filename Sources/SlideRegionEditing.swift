import Foundation

enum SlideRegionHandle: CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight, top, bottom, left, right
    var adjustsLeft: Bool { self == .left || self == .topLeft || self == .bottomLeft }
    var adjustsRight: Bool { self == .right || self == .topRight || self == .bottomRight }
    var adjustsTop: Bool { self == .top || self == .topLeft || self == .topRight }
    var adjustsBottom: Bool { self == .bottom || self == .bottomLeft || self == .bottomRight }
    func point(in rect: CGRect) -> CGPoint {
        CGPoint(x: adjustsLeft ? rect.minX : adjustsRight ? rect.maxX : rect.midX,
                y: adjustsTop ? rect.minY : adjustsBottom ? rect.maxY : rect.midY)
    }
    func hitArea(in rect: CGRect) -> CGRect {
        let point = point(in: rect)
        return CGRect(x: point.x - 7, y: point.y - 7, width: 14, height: 14)
    }
}

// Edits stay local to the selector until Apply. A drag is one undoable change;
// invalid drops never replace the last valid crop used by OCR.
struct SlideRegionEditing {
    private struct Snapshot {
        var regions: [CGRect]
        var selected: Int?
    }
    enum Hit {
        case move(Int), resize(Int, SlideRegionHandle)
    }
    private struct Drag {
        let start: CGPoint
        let bounds: CGRect
        let hit: Hit?
        let before: Snapshot
    }
    private var history: [Snapshot] = []
    private var drag: Drag?
    private(set) var regions: [CGRect]
    private(set) var selected: Int?
    private(set) var preview: CGRect?
    private(set) var previewIsValid = false
    private(set) var notice: String?
    var isDragging: Bool { drag != nil }
    var canUndo: Bool { !history.isEmpty }
    var editingIndex: Int? {
        switch drag?.hit { case .move(let i), .resize(let i, _): return i; default: return nil }
    }
    init(regions: [CGRect]) { self.regions = regions; selected = regions.indices.last }

    func hit(at point: CGPoint, in bounds: CGRect) -> Hit? {
        let indices = regions.indices.reversed().filter { $0 != selected }
        let ordered = selected.map { [$0] + indices } ?? Array(indices)
        for i in ordered {
            let rect = SlideRegionGeometry.absolute(regions[i], in: bounds)
            for handle in SlideRegionHandle.allCases where handle.hitArea(in: rect).contains(point) {
                return .resize(i, handle)
            }
            // The entire border resizes, not just the visible handles.
            if rect.insetBy(dx: -5, dy: -5).contains(point) {
                if abs(point.x - rect.minX) <= 5 { return .resize(i, .left) }
                if abs(point.x - rect.maxX) <= 5 { return .resize(i, .right) }
                if abs(point.y - rect.minY) <= 5 { return .resize(i, .top) }
                if abs(point.y - rect.maxY) <= 5 { return .resize(i, .bottom) }
            }
            if rect.contains(point) { return .move(i) }
        }
        return nil
    }
    mutating func begin(at point: CGPoint, in bounds: CGRect) {
        guard bounds.width >= 12, bounds.height >= 12 else { return }
        let hit = hit(at: point, in: bounds)
        guard hit != nil || bounds.contains(point) else { return }
        let before = Snapshot(regions: regions, selected: selected)
        switch hit { case .move(let i), .resize(let i, _): selected = i; default: selected = nil }
        drag = Drag(start: point, bounds: bounds, hit: hit, before: before)
        notice = nil; update(to: point)
    }
    mutating func update(to point: CGPoint) {
        guard let drag else { return }
        let bounds = drag.bounds
        let dx = point.x - drag.start.x, dy = point.y - drag.start.y
        let rect: CGRect
        switch drag.hit {
        case .move(let i):
            let original = SlideRegionGeometry.absolute(drag.before.regions[i], in: bounds)
            rect = CGRect(x: min(max(original.minX + dx, bounds.minX), bounds.maxX - original.width),
                          y: min(max(original.minY + dy, bounds.minY), bounds.maxY - original.height),
                          width: original.width, height: original.height)
        case .resize(let i, let handle):
            let original = SlideRegionGeometry.absolute(drag.before.regions[i], in: bounds)
            let minWidth = min(12, original.width), minHeight = min(12, original.height)
            let left = handle.adjustsLeft ? max(bounds.minX, min(original.minX + dx, original.maxX - minWidth)) : original.minX
            let right = handle.adjustsRight ? min(bounds.maxX, max(original.maxX + dx, original.minX + minWidth)) : original.maxX
            let top = handle.adjustsTop ? max(bounds.minY, min(original.minY + dy, original.maxY - minHeight)) : original.minY
            let bottom = handle.adjustsBottom ? min(bounds.maxY, max(original.maxY + dy, original.minY + minHeight)) : original.maxY
            rect = CGRect(x: left, y: top, width: right - left, height: bottom - top)
        case nil:
            rect = CGRect(x: min(drag.start.x, point.x), y: min(drag.start.y, point.y), width: abs(dx), height: abs(dy)).intersection(bounds)
        }
        // Existing tiny crops remain movable after resizing the preview window.
        if rect.isNull || rect.width <= 0 || rect.height <= 0 { preview = nil }
        else {
            preview = CGRect(x: (rect.minX - bounds.minX) / bounds.width, y: (rect.minY - bounds.minY) / bounds.height,
                             width: rect.width / bounds.width, height: rect.height / bounds.height)
        }
        let bigEnough = drag.hit != nil || (rect.width >= 12 && rect.height >= 12)
        previewIsValid = bigEnough && preview.map { candidate in
            !regions.indices.contains { i in
                guard i != editingIndex else { return false }
                let overlap = regions[i].intersection(candidate)
                return !overlap.isNull && overlap.width > 0.000001 && overlap.height > 0.000001
            }
        } == true
    }
    mutating func end(at point: CGPoint) {
        guard let drag else { return }
        update(to: point)
        if let preview, previewIsValid {
            if let index = editingIndex {
                let old = regions[index]
                let difference = abs(old.minX - preview.minX) + abs(old.minY - preview.minY)
                    + abs(old.width - preview.width) + abs(old.height - preview.height)
                if difference > 0.000000001 { regions[index] = preview }
            }
            else { regions.append(preview); selected = regions.count - 1 }
            if regions != drag.before.regions { history.append(drag.before) }
        } else if abs(point.x - drag.start.x) > 3 || abs(point.y - drag.start.y) > 3 {
            notice = preview != nil && (preview!.width * drag.bounds.width >= 12 && preview!.height * drag.bounds.height >= 12)
                ? "別の枠と重なるため変更していません。枠を移動するか、小さくしてください。"
                : "もう少し大きな範囲をドラッグしてください。"
        }
        self.drag = nil; preview = nil
    }
    mutating func cancelDrag() {
        if let drag { selected = drag.before.selected }
        drag = nil; preview = nil; notice = nil
    }
    mutating func undo() {
        cancelDrag()
        guard let before = history.popLast() else { return }
        regions = before.regions; selected = before.selected
    }
    mutating func deleteSelected() {
        cancelDrag()
        guard let selected else { return }
        history.append(Snapshot(regions: regions, selected: selected))
        regions.remove(at: selected); self.selected = regions.indices.last
    }
    mutating func clear() {
        cancelDrag()
        guard !regions.isEmpty else { return }
        history.append(Snapshot(regions: regions, selected: selected))
        regions = []; selected = nil
    }
}
