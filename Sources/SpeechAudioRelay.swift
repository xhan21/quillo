import AVFoundation
import Foundation

// The microphone owns one tap for its entire lifetime. Recognition requests can
// detach without losing buffers arriving before the replacement is ready.
final class SpeechAudioRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var active = true
    private var sink: ((AVAudioPCMBuffer) -> Void)?
    private var owner: UUID?
    private var pending: [AVAudioPCMBuffer] = []
    private var pendingDuration: TimeInterval = 0
    private var quietDuration: TimeInterval = 0
    private let capacity: TimeInterval
    var onOverflow: (() -> Void)?

    init(capacity: TimeInterval = 8) { self.capacity = capacity }

    var quietSeconds: TimeInterval {
        lock.lock(); defer { lock.unlock() }; return quietDuration
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        guard active, buffer.frameLength > 0 else { lock.unlock(); return }
        let duration = Double(buffer.frameLength) / buffer.format.sampleRate
        // This only chooses a convenient rollover boundary; it never gates audio.
        var peak: Float = 1
        if let channels = buffer.floatChannelData {
            peak = 0
            for channel in 0..<Int(buffer.format.channelCount) {
                for frame in 0..<Int(buffer.frameLength) {
                    peak = max(peak, abs(channels[channel][frame * buffer.stride]))
                }
            }
        }
        quietDuration = peak < 0.003 ? quietDuration + duration : 0
        if let sink {
            sink(buffer)
            lock.unlock()
        } else if pendingDuration + duration <= capacity, let copy = Self.copy(buffer) {
            pending.append(copy); pendingDuration += duration
            lock.unlock()
        } else {
            // Never silently drop the onset of a phrase when recognition stalls.
            active = false; pending.removeAll(); pendingDuration = 0
            let report = onOverflow
            lock.unlock(); report?()
        }
    }

    func prepare(_ id: UUID) {
        lock.lock(); defer { lock.unlock() }
        guard active else { return }
        owner = id; sink = nil
    }

    func attach(_ id: UUID, sink: @escaping (AVAudioPCMBuffer) -> Void) {
        lock.lock(); defer { lock.unlock() }
        guard active, owner == id else { return }
        for buffer in pending { sink(buffer) }
        pending.removeAll(); pendingDuration = 0
        self.sink = sink
    }

    func detach(_ id: UUID) {
        lock.lock(); defer { lock.unlock() }
        guard owner == id else { return }
        sink = nil; owner = nil
    }

    func stop() {
        lock.lock(); defer { lock.unlock() }
        active = false; sink = nil; owner = nil; pending.removeAll(); pendingDuration = 0
    }

    private static func copy(_ source: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let target = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: source.frameLength) else { return nil }
        target.frameLength = source.frameLength
        let input = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: source.audioBufferList))
        let output = UnsafeMutableAudioBufferListPointer(target.mutableAudioBufferList)
        for index in input.indices {
            guard let src = input[index].mData, let dst = output[index].mData else { return nil }
            memcpy(dst, src, Int(input[index].mDataByteSize))
        }
        return target
    }
}
