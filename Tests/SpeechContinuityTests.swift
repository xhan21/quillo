import AVFoundation
import Foundation

private final class FakeSession: SpeechRecognitionSession {
    let id: UUID
    let event: (SpeechRecognitionEvent) -> Void
    var frames: [Float] = []
    var ended = false
    var cancelled = false
    init(_ id: UUID, _ event: @escaping (SpeechRecognitionEvent) -> Void) { self.id = id; self.event = event }
    func append(_ buffer: AVAudioPCMBuffer) { frames += Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength))) }
    func endAudio() { ended = true }
    func cancel() { cancelled = true }
    func text(_ text: String, final: Bool = false) { event(.init(snapshot: .init(segmentID: id, text: text), isFinal: final)) }
}

@main enum SpeechContinuityTests {
    static func buffer(_ values: [Float]) -> AVAudioPCMBuffer {
        let b = AVAudioPCMBuffer(pcmFormat: AVAudioFormat(standardFormatWithSampleRate: 1000, channels: 1)!, frameCapacity: AVAudioFrameCount(values.count))!
        b.frameLength = b.frameCapacity
        for (index, value) in values.enumerated() { b.floatChannelData![0][index] = value }
        return b
    }
    @MainActor static func settle() async { try? await Task.sleep(for: .milliseconds(20)) }
    @MainActor static func main() async {
        // Audio-tap buffers are reused by AVAudioEngine: pending PCM must own a copy.
        let relay = SpeechAudioRelay(), first = UUID(), second = UUID()
        let initial = buffer([1, 2, 3]); relay.append(initial)
        initial.floatChannelData![0][0] = 99
        var received: [Float] = []
        let collect: (AVAudioPCMBuffer) -> Void = { b in received += Array(UnsafeBufferPointer(start: b.floatChannelData![0], count: Int(b.frameLength))) }
        relay.prepare(first); relay.attach(first, sink: collect)
        relay.append(buffer([4, 5])); relay.detach(first)
        relay.append(buffer([6, 7])); relay.append(buffer([8, 9]))
        relay.prepare(second); relay.attach(second, sink: collect)
        relay.detach(first) // A delayed old callback cannot disconnect the new sink.
        relay.append(buffer([10]))
        precondition(received == (1...10).map(Float.init), "Every captured frame arrives once, in order, across startup and handoff")
        relay.stop(); relay.append(buffer([11])); relay.prepare(UUID())
        precondition(received.count == 10)

        let bounded = SpeechAudioRelay(capacity: 0.004)
        var overflow = 0
        bounded.onOverflow = { overflow += 1 }
        bounded.append(buffer([1, 2, 3])); bounded.append(buffer([4, 5])); bounded.append(buffer([6]))
        precondition(overflow == 1, "A stalled request must report overflow, never silently trim an onset")

        var sessions: [FakeSession] = [], outputs: [(String, Bool)] = []
        var errors: [String] = []
        let stream = SpeechRecognitionStream(drainSeconds: 0.06) { id, phrases, event in
            precondition(phrases == ["大丈夫", "ちゃんと"])
            let s = FakeSession(id, event); sessions.append(s); return s
        }
        stream.phrases = { ["大丈夫", "ちゃんと"] }
        stream.onText = { outputs.append(($0.text, $1)) }; stream.onFailure = { errors.append($0) }
        stream.audio.append(buffer([1])); stream.start()
        sessions[0].text("最初です")
        await settle()
        stream.rotate(); stream.rotate()
        precondition(sessions[0].ended && sessions.count == 1)
        stream.audio.append(buffer([2, 3]))
        sessions[0].text("最初です。", final: true)
        await settle()
        precondition(sessions.count == 2 && sessions[0].frames == [1] && sessions[1].frames == [2, 3])
        stream.audio.append(buffer([4]))
        sessions[0].text("古い結果", final: true)
        await settle()
        precondition(sessions.count == 2 && !outputs.contains { $0.0 == "古い結果" })
        sessions[1].text("ちゃんと聞こえます")
        await settle()
        stream.rotate(); stream.audio.append(buffer([5, 6]))
        try? await Task.sleep(for: .milliseconds(100))
        precondition(sessions.count == 3 && sessions[2].frames == [5, 6], "Missing final result must not stall the handoff")
        precondition(outputs.filter { $0.0 == "ちゃんと聞こえます" && $0.1 }.count == 1)
        sessions[2].event(.init(errorCode: 1101))
        stream.audio.append(buffer([7])) // Before UI callback handles the error.
        await settle()
        precondition(sessions.count == 4 && sessions[3].frames == [7])
        precondition(sessions.flatMap(\.frames) == (1...7).map(Float.init))
        stream.rotate(); stream.audio.append(buffer([8])); stream.stop()
        sessions[3].text("停止後", final: true)
        try? await Task.sleep(for: .milliseconds(100))
        precondition(sessions.count == 4 && !outputs.contains { $0.0 == "停止後" } && errors.isEmpty)

        // An immediate failure during session construction must not reattach a
        // closed request; the buffered onset belongs to its replacement.
        var immediate: [FakeSession] = []
        let startup = SpeechRecognitionStream { id, _, event in
            let s = FakeSession(id, event); immediate.append(s)
            if immediate.count == 1 { event(.init(errorCode: 1101)) }
            return s
        }
        startup.audio.append(buffer([12, 13])); startup.start()
        await settle()
        precondition(immediate.count == 2 && immediate[0].frames.isEmpty && immediate[1].frames == [12, 13])
        immediate[1].event(.init(errorCode: 1700))
        await settle()
        startup.audio.append(buffer([14])); await settle()
        precondition(immediate.count == 2 && immediate[1].frames == [12, 13])
        var paused: [FakeSession] = []
        let quietStream = SpeechRecognitionStream(drainSeconds: 0.06) { id, _, event in
            let s = FakeSession(id, event); paused.append(s); return s
        }
        quietStream.start(); quietStream.audio.append(buffer([0.5]))
        paused[0].text("ちゃんと聞こえます")
        await settle()
        quietStream.audio.append(buffer(Array(repeating: 0, count: 900)))
        try? await Task.sleep(for: .milliseconds(240))
        precondition(paused.count == 2 && paused[0].ended, "An utterance's quiet tail rolls recognition without stopping capture")
        quietStream.audio.append(buffer([0.5, 0.6]))
        precondition(paused[1].frames == [0.5, 0.6], "The next onset belongs to the fresh request")
        quietStream.stop()
        print("PASS: continuous PCM, copied opening buffers, ordered handoff, bounded buffering, final drain/timeout, stale callbacks, recoverable/fatal errors and explicit stop")
    }
}
