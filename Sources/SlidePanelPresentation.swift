import AppKit
import Combine

@MainActor
final class SlidePanelPresentation: ObservableObject {
    @Published private(set) var layout = SlidePanelLayout(fontSize: 16, pages: [])
    @Published private(set) var page = 0
    @Published var automatic = true { didSet { schedule() } }
    private var text = "", revision = -1
    private var size = CGSize(width: 400, height: 400)
    private var preferred = 16.0
    private var active = false
    private var timer: Task<Void, Never>?
    var currentText: String { layout.pages.indices.contains(page) ? layout.pages[page].text : "" }
    func update(text: String, revision: Int, preferred: Double) {
        guard text != self.text || revision != self.revision || preferred != self.preferred else { return }
        let newPage = revision != self.revision
        self.text = text; self.revision = revision; self.preferred = preferred
        reflow(reset: newPage)
    }
    func resize(_ size: CGSize) {
        guard size.width > 40, size.height > 40, self.size != size else { return }
        self.size = size; reflow(reset: false)
    }
    private func reflow(reset: Bool) {
        let anchor = reset ? 0 : (layout.pages.indices.contains(page) ? layout.pages[page].start : 0)
        layout = SlidePanelTypesetting.fit(text, size: size, preferredFontSize: preferred)
        page = layout.pages.firstIndex { $0.start <= anchor && anchor < $0.end } ?? 0
        schedule()
    }
    func setActive(_ value: Bool) { active = value; schedule() }
    func step(_ delta: Int) {
        guard !layout.pages.isEmpty else { return }
        page = (page + delta + layout.pages.count) % layout.pages.count; schedule()
    }
    private func schedule() {
        timer?.cancel(); timer = nil
        guard active, automatic, layout.pages.count > 1 else { return }
        let duration = SlidePanelTypesetting.displayDuration(currentText)
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.step(1)
        }
    }
}
