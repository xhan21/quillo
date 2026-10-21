import AppKit
import AVFoundation
import Speech

@MainActor
final class SpeechCapture {
    var contextualPhrases: [String] = []
    var onText: ((SpeechSnapshot, Bool) -> Void)?
    var onStatus: ((String) -> Void)?
    var onStarted: (() -> Void)?
    var onStopped: (() -> Void)?
    private var engine: AVAudioEngine?
    private var tapInstalled = false
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var rollover: Task<Void, Never>?
    private var recognizer: SFSpeechRecognizer?
    private var generation = 0
    private var running = false
    private var restarting = false
    private var failures = 0
    private var currentSnapshot: SpeechSnapshot?

    func start(language: CaptionLanguage) async {
        stop(notify: false)
        guard language.supportsSpeechInput else {
            onStatus?("音声入力は日本語・英語に対応しています。")
            onStopped?(); return
        }
        generation += 1
        let startGeneration = generation
        var speechPermission = SFSpeechRecognizer.authorizationStatus()
        if speechPermission == .notDetermined {
            speechPermission = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
        }
        guard startGeneration == generation else { return }
        guard speechPermission == .authorized else {
            onStatus?("音声認識の許可が必要です。システム設定の「プライバシーとセキュリティ」から許可してください。")
            onStopped?(); return
        }
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        var micPermission = micStatus == .authorized
        if micStatus == .notDetermined {
            micPermission = await AVCaptureDevice.requestAccess(for: .audio)
        }
        guard startGeneration == generation else { return }
        guard micPermission else {
            onStatus?("マイクが許可されていません。システム設定の「プライバシーとセキュリティ」→「マイク」を確認してください。")
            onStopped?(); return
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language.speechLocale)), recognizer.supportsOnDeviceRecognition else {
            onStatus?("\(language.dictationName)の端末内音声認識を利用できません。Macの「システム設定 → キーボード → 音声入力 → 言語」を確認してください。文字入力・資料要約は使えます。")
            onStopped?(); return
        }
        self.recognizer = recognizer
        running = true; failures = 0
        beginSegment()
    }

    private func beginSegment() {
        guard running, let recognizer else { return }
        generation += 1
        let segmentGeneration = generation
        let segmentID = UUID()
        cleanupSegment()
        restarting = false; currentSnapshot = nil
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        request.contextualStrings = Array(contextualPhrases.prefix(100))
        self.request = request
        let engine = AVAudioEngine()
        self.engine = engine
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            fail("利用できるマイク入力がありません。Macの入力デバイスを確認してください。"); return
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
        tapInstalled = true
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let snapshot = result.map { result in
                SpeechSnapshot(segmentID: segmentID, text: result.bestTranscription.formattedString,
                    words: result.bestTranscription.segments.map { SpeechWord(range: $0.substringRange, timestamp: $0.timestamp, duration: $0.duration) })
            }
            let isFinal = result?.isFinal ?? false
            let errorDescription = error?.localizedDescription
            let errorCode = (error as NSError?)?.code
            Task { @MainActor in
                guard let self, self.running, self.generation == segmentGeneration else { return }
                if let snapshot, !snapshot.text.isEmpty {
                    self.currentSnapshot = snapshot; self.failures = 0
                    self.onText?(snapshot, isFinal)
                }
                if isFinal {
                    self.currentSnapshot = nil
                    self.scheduleRestart()
                } else if errorDescription != nil {
                    self.failures += 1
                    if errorCode == 201 {
                        self.fail("Macの音声入力が無効です。システム設定の「キーボード」→「音声入力」を有効にしてから再開してください。")
                    } else if errorCode == 1700 {
                        self.fail("音声認識が許可されていません。システム設定の「プライバシーとセキュリティ」→「音声認識」で、このアプリの許可を確認してください。")
                    } else if errorCode == 102 {
                        self.fail("選択した言語の音声データがありません。Macの「キーボード」→「音声入力」で言語を追加してください。")
                    } else if self.failures > 3 {
                        self.fail("音声認識が続けて停止しました。マイクとmacOSの音声入力設定を確認して、再開してください。")
                    } else {
                        self.scheduleRestart()
                    }
                }
            }
        }
        do {
            engine.prepare(); try engine.start()
            onStarted?()
            onStatus?("マイクで聴いています。音声はこのMac内で認識します。")
            rollover = Task { [weak self] in
                try? await Task.sleep(for: .seconds(50))
                guard !Task.isCancelled, let self, self.running, self.generation == segmentGeneration else { return }
                if let snapshot = self.currentSnapshot { self.onText?(snapshot, true); self.currentSnapshot = nil }
                self.scheduleRestart()
            }
        } catch { fail("マイクを開始できませんでした：\(error.localizedDescription)") }
    }

    private func scheduleRestart() {
        guard running, !restarting else { return }
        restarting = true
        if let snapshot = currentSnapshot { onText?(snapshot, true); currentSnapshot = nil }
        generation += 1
        let restartGeneration = generation
        cleanupSegment()
        rollover = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self, self.running, self.generation == restartGeneration else { return }
            self.beginSegment()
        }
    }

    private func cleanupSegment() {
        rollover?.cancel(); rollover = nil
        if let engine {
            engine.stop()
            if tapInstalled { engine.inputNode.removeTap(onBus: 0) }
        }
        tapInstalled = false
        request?.endAudio(); task?.cancel()
        engine = nil; request = nil; task = nil
    }

    private func fail(_ message: String) { stop(notify: false); onStatus?(message); onStopped?() }

    func stop(notify: Bool = true) {
        running = false; generation += 1; restarting = false
        if let snapshot = currentSnapshot { onText?(snapshot, true); currentSnapshot = nil }
        cleanupSegment()
        recognizer = nil
        if notify { onStatus?("マイクを停止しました。"); onStopped?() }
    }
}
