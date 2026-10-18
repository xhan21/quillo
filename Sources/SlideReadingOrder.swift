import AppKit

enum SlideReadingOrder: String, CaseIterable, Identifiable {
    case rows, columns
    var id: String { rawValue }
    var name: String { self == .rows ? "行順（横に読んでから次の行）" : "列順（左の段 → 右の段）" }
}

// Column ordering adapted from xhan21/class-material-translator (MIT).
// See Resources/ClassMaterialTranslator-LICENSE.txt.
enum SlideTextOrdering {
    static func ordered(_ blocks: [SlideTextBlock], mode: SlideReadingOrder, depth: Int = 0) -> [SlideTextBlock] {
        let rows = blocks.sorted { $0.rect.minY == $1.rect.minY ? $0.rect.minX < $1.rect.minX : $0.rect.minY < $1.rect.minY }
        guard mode == .columns, rows.count > 1, depth < 12 else { return rowOrder(rows) }
        let heights = rows.map { $0.rect.height }.sorted()
        let height = heights[heights.count / 2]
        let edges = Array(Set(rows.flatMap { [$0.rect.minX, $0.rect.maxX] })).sorted()
        var best: (gap: CGFloat, left: [SlideTextBlock], right: [SlideTextBlock], header: [SlideTextBlock], footer: [SlideTextBlock])?
        for i in 1..<edges.count {
            let gap = edges[i] - edges[i - 1]
            guard gap >= max(4, height * 0.35) else { continue }
            let cut = (edges[i] + edges[i - 1]) / 2
            let left = rows.filter { $0.rect.maxX <= cut }, right = rows.filter { $0.rect.minX >= cut }
            guard let l = left.first, let r = right.first else { continue }
            let top = max(l.rect.minY, r.rect.minY)
            let bottom = min(left.map { $0.rect.maxY }.max()!, right.map { $0.rect.maxY }.max()!)
            guard bottom - top >= height * 0.5,
                  left.contains(where: { a in right.contains { b in min(a.rect.maxY, b.rect.maxY) - max(a.rect.minY, b.rect.minY) >= min(a.rect.height, b.rect.height) * 0.3 } }) else { continue }
            let spanning = rows.filter { $0.rect.minX < cut && $0.rect.maxX > cut }
            let header = spanning.filter { $0.rect.maxY <= top }, footer = spanning.filter { $0.rect.minY >= bottom }
            guard header.count + footer.count == spanning.count,
                  !header.contains(where: { h in (left + right).contains { $0.rect.minY < h.rect.maxY } }),
                  !footer.contains(where: { f in (left + right).contains { $0.rect.maxY > f.rect.minY } }) else { continue }
            if best == nil || gap > best!.gap { best = (gap, left, right, header, footer) }
        }
        if let best {
            return best.header + ordered(best.left, mode: mode, depth: depth + 1) + ordered(best.right, mode: mode, depth: depth + 1) + best.footer
        }
        var edge = rows[0].rect.maxY, largest = height * 1.5
        var split: Int?
        for i in 1..<rows.count {
            let gap = rows[i].rect.minY - edge
            if gap > largest { split = i; largest = gap }
            edge = max(edge, rows[i].rect.maxY)
        }
        guard let split else { return rowOrder(rows) }
        return ordered(Array(rows[..<split]), mode: mode, depth: depth + 1) + ordered(Array(rows[split...]), mode: mode, depth: depth + 1)
    }
    private static func rowOrder(_ blocks: [SlideTextBlock]) -> [SlideTextBlock] {
        var groups: [[SlideTextBlock]] = []
        for block in blocks {
            if let i = groups.indices.last, let anchor = groups[i].first,
               abs(anchor.rect.midY - block.rect.midY) <= min(anchor.rect.height, block.rect.height) * 0.45 {
                groups[i].append(block)
            } else { groups.append([block]) }
        }
        return groups.flatMap { $0.sorted { $0.rect.minX < $1.rect.minX } }
    }
}

enum SlideRegionGeometry {
    static let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
    static func normalized(_ rect: CGRect, in bounds: CGRect) -> CGRect? {
        let clipped = rect.standardized.intersection(bounds)
        guard !clipped.isNull, clipped.width >= 12, clipped.height >= 12, bounds.width > 0, bounds.height > 0 else { return nil }
        return CGRect(x: (clipped.minX - bounds.minX) / bounds.width, y: (clipped.minY - bounds.minY) / bounds.height, width: clipped.width / bounds.width, height: clipped.height / bounds.height)
    }
    static func absolute(_ rect: CGRect, in bounds: CGRect) -> CGRect {
        CGRect(x: bounds.minX + rect.minX * bounds.width, y: bounds.minY + rect.minY * bounds.height, width: rect.width * bounds.width, height: rect.height * bounds.height)
    }
}
