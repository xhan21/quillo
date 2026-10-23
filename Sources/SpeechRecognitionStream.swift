import AVFoundation
import Speech

struct SpeechRecognitionEvent {
    var snapshot: SpeechSnapshot?
    var isFinal = false
    var errorCode: Int?
}

protocol SpeechRecognitionSession: AnyObject {
    func append(_ buffer: AVAudioPCMBuffer)
    func endAudio()
    func cancel()
}

private final class AppleSpeechSession: SpeechRecognitionSession {
    private let request = SFSpeechAudioBufferRecognitionRequest()
    private var task: SFSpeechRecognitionTask?

    init(recognizer: SFSpeechRecognizer, id: UUID, phrases: [String], event: @escaping (SpeechRecognitionEvent) -> Void) {
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        request.contextualStrings = Array(phrases.prefix(100))
        task = recognizer.recognitionTask(with: request) { result, error in
            let snapshot = result.map {
                SpeechSnapshot(segmentID: id, text: $0.bestTranscription.formattedString,
                    words: $0.bestTranscription.segments.map { SpeechWord(range: $0.substringRange, timestamp: $0.timestamp, duration: $0.duration) })
            }
            event(SpeechRecognitionEvent(snapshot: snapshot, isFinal: result?.isFinal ?? false, errorCode: (error as NSError?)?.code))
        }
    }
    func append(_ buffer: AVAudioPCMBuffer) { request.append(buffer) }
    func endAudio() { request.endAudio() }
    func cancel() { task?.cancel(); task = nil }
}

// Independent of microphone acquisition so the real handoff can also be tested
// with synthetic PCM. Every buffer goes to exactly one recognition request.
@MainActor final class SpeechRecognitionStream {
    typealias Factory = (UUID, [String], @escaping (SpeechRecognitionEvent) -> Void) -> SpeechRecognitionSession
    let audio = SpeechAudioRelay()
    var phrases: () -> [String] = { [] }
    var onText: ((SpeechSnapshot, Bool) -> Void)?
    var onFailure: ((String) -> Void)?
    private let factory: Factory
    private var session: SpeechRecognitionSession?
    private var id: UUID?
    private var currentSnapshot: SpeechSnapshot?
    private var running = false
    private var draining = false
    private var failures = 0
    private var rollover: Task<Void, Never>?
    private var drainDeadline: Task<Void, Never>?
    private let drainSeconds: Double
    private let pauseRollover: Bool

    convenience init(recognizer: SFSpeechRecognizer, pauseRollover: Bool = true) {
        self.init(pauseRollover: pauseRollover) { id, phrases, event in AppleSpeechSession(recognizer: recognizer, id: id, phrases: phrases, event: event) }
    }
    init(drainSeconds: Double = 1.5, pauseRollover: Bool = true, factory: @escaping Factory) {
        self.factory = factory; self.drainSeconds = drainSeconds; self.pauseRollover = pauseRollover
        audio.onOverflow = { [weak self] in
            Task { @MainActor in self?.fail("音声認識の切り替えが遅れています。字幕を停止しました。もう一度開始してください。") }
        }
    }

    func start() {
        guard !running else { return }
        running = true; beginSegment()
    }

    private func beginSegment() {
        guard running else { return }
        let nextID = UUID()
        id = nextID; draining = false; currentSnapshot = nil
        let audio = self.audio
        audio.prepare(nextID)
        let next = factory(nextID, phrases()) { [weak self] event in
            // Detach on the callback thread, before waiting for the UI thread.
            if event.isFinal || event.errorCode != nil { audio.detach(nextID) }
            Task { @MainActor in self?.receive(event, for: nextID) }
        }
        session = next
        audio.attach(nextID) { [next] buffer in next.append(buffer) }
        rollover = Task { [weak self] in
            let started = ContinuousClock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled, let self, self.running, self.id == nextID else { return }
                let elapsed = started.duration(to: .now)
                // Rotate during quiet *before* the recognizer resets its text
                // internally. New speech arriving during finalization is queued.
                let phraseEnded = self.pauseRollover && self.currentSnapshot != nil && self.audio.quietSeconds >= 0.8
                let periodic = elapsed >= .seconds(50) && self.audio.quietSeconds >= 0.4
                if phraseEnded || periodic || elapsed >= .seconds(55) {
                    self.rotate(); return
                }
            }
        }
    }

    // End only the recognition request. Continue buffering the live tap while
    // its final result drains, so the next word is not sent into a closing task.
    func rotate() {
        guard running, !draining, let id else { return }
        draining = true; rollover?.cancel(); rollover = nil
        audio.detach(id); session?.endAudio()
        drainDeadline = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(self.drainSeconds))
            guard !Task.isCancelled, self.running, self.id == id else { return }
            self.finishSegment()
        }
    }

    private func receive(_ event: SpeechRecognitionEvent, for eventID: UUID) {
        guard running, id == eventID else { return }
        if let snapshot = event.snapshot, !snapshot.text.isEmpty {
            currentSnapshot = event.isFinal ? nil : snapshot; failures = 0
            onText?(snapshot, event.isFinal)
        }
        if event.isFinal { finishSegment(); return }
        guard let code = event.errorCode else { return }
        failures += 1
        switch code {
        case 201: fail("Macの音声入力が無効です。システム設定の「キーボード」→「音声入力」を有効にしてから再開してください。")
        case 1700: fail("音声認識が許可されていません。システム設定の「プライバシーとセキュリティ」→「音声認識」で、このアプリの許可を確認してください。")
        case 102: fail("選択した言語の音声データがありません。Macの「キーボード」→「音声入力」で言語を追加してください。")
        default:
            if failures > 3 { fail("音声認識が続けて停止しました。マイクとmacOSの音声入力設定を確認して、再開してください。") }
            else { finishSegment() }
        }
    }

    private func finishSegment() {
        guard running else { return }
        retireSegment(); beginSegment()
    }

    private func retireSegment() {
        if let id { audio.detach(id) }
        id = nil
        rollover?.cancel(); rollover = nil
        drainDeadline?.cancel(); drainDeadline = nil
        if let snapshot = currentSnapshot { onText?(snapshot, true); currentSnapshot = nil }
        session?.cancel(); session = nil; draining = false
    }

    func stop() {
        running = false
        audio.stop(); retireSegment()
    }

    private func fail(_ message: String) {
        guard running else { return }
        stop(); onFailure?(message)
    }
}
