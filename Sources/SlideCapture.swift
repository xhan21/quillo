import AppKit
import ScreenCaptureKit
import CoreImage

struct SlideFrame {
    let image: CGImage
    let quartzFrame: CGRect
    let isWindow: Bool
}

@MainActor
final class SlideCapture: NSObject, SCContentSharingPickerObserver, SCStreamDelegate, SCStreamOutput {
    var onFrame: ((SlideFrame) -> Void)?
    var onSelection: ((String) -> Void)?
    var onCancelled: (() -> Void)?
    var onStopped: ((String) -> Void)?
    var onUnavailable: (() -> Void)?
    private var stream: SCStream?
    private var fallbackFrame = CGRect.zero
    private var windowCapture = false
    private var generation = 0
    private let queue = DispatchQueue(label: "jp.xuhan.kotoba.slide-capture", qos: .userInitiated)
    private nonisolated let imageContext = CIContext(options: [.cacheIntermediates: false])

    override init() {
        super.init()
        SCContentSharingPicker.shared.add(self)
    }
    func select() {
        var configuration = SCContentSharingPickerConfiguration()
        configuration.allowedPickerModes = [.singleDisplay, .singleWindow]
        configuration.excludedWindowIDs = NSApp.windows.map { $0.windowNumber }
        configuration.allowsChangingSelectedContent = true
        let picker = SCContentSharingPicker.shared
        picker.defaultConfiguration = configuration
        picker.isActive = true
        if let stream { picker.present(for: stream) } else { picker.present() }
    }
    func stop() {
        generation += 1
        let previous = stream; stream = nil
        if let previous { Task { try? await previous.stopCapture() } }
        SCContentSharingPicker.shared.isActive = false
    }
    private func start(_ filter: SCContentFilter) async {
        guard SCContentSharingPicker.shared.isActive else { return }
        generation += 1; let token = generation
        let previous = stream; stream = nil
        if let previous { try? await previous.stopCapture() }
        guard token == generation else { return }
        fallbackFrame = filter.contentRect
        windowCapture = filter.style == .window
        var name = windowCapture ? "選択したウィンドウ" : "選択した画面"
        if #available(macOS 15.2, *) {
            if let window = filter.includedWindows.first, windowCapture { fallbackFrame = window.frame; name = window.title ?? name }
            if let display = filter.includedDisplays.first, !windowCapture { fallbackFrame = display.frame }
        }
        let configuration = SCStreamConfiguration()
        let factor = min(2.0, 2560 / max(1, filter.contentRect.width))
        configuration.width = max(1, Int(filter.contentRect.width * factor))
        configuration.height = max(1, Int(filter.contentRect.height * factor))
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 2)
        configuration.queueDepth = 3
        configuration.showsCursor = false
        configuration.capturesAudio = false; configuration.captureMicrophone = false
        configuration.ignoreShadowsSingleWindow = true; configuration.ignoreShadowsDisplay = true
        configuration.includeChildWindows = false
        configuration.scalesToFit = true
        // Fill the output surface. OCR coordinates are normalized back to the
        // current onscreen rectangle, so window resizing cannot add letterboxing.
        configuration.preservesAspectRatio = false
        configuration.streamName = "Quillo・資料の要約"
        let next = SCStream(filter: filter, configuration: configuration, delegate: self)
        stream = next
        onSelection?(name)
        do {
            try next.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
            try await next.startCapture()
            guard token == generation else { try? await next.stopCapture(); return }
        } catch {
            guard token == generation else { return }
            stream = nil; onStopped?("画面の読み取りを開始できませんでした。画面の共有許可と、選択した資料を確認してください。")
        }
    }
    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        Task { @MainActor in await self.start(filter) }
    }
    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        Task { @MainActor in self.onCancelled?() }
    }
    nonisolated func contentSharingPickerStartDidFailWithError(_ error: Error) {
        Task { @MainActor in self.onStopped?("画面選択を開けませんでした。もう一度「画面を選ぶ」を押してください。") }
    }
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            guard self.stream === stream else { return }
            self.stream = nil; self.onStopped?("画面の読み取りを終了しました。再開するには画面を選び直してください。")
        }
    }
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let info = attachments.first,
              let status = info[.status] as? Int else { return }
        if status == SCFrameStatus.suspended.rawValue || status == SCFrameStatus.blank.rawValue || status == SCFrameStatus.stopped.rawValue {
            Task { @MainActor in if self.stream === stream { self.onUnavailable?() } }
            return
        }
        guard status == SCFrameStatus.complete.rawValue, let buffer = sampleBuffer.imageBuffer else { return }
        let ci = CIImage(cvPixelBuffer: buffer)
        guard let image = imageContext.createCGImage(ci, from: ci.extent) else { return }
        let screenRect = (info[.screenRect] as? [String: Any]).flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) }
        Task { @MainActor in
            guard self.stream === stream else { return }
            let rect = screenRect.flatMap { $0.width > 0 && $0.height > 0 ? $0 : nil } ?? self.fallbackFrame
            self.onFrame?(SlideFrame(image: image, quartzFrame: rect, isWindow: self.windowCapture))
        }
    }
}
