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
    private var stream: SpeechRecognitionStream?
    private var generation = 0

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
        let stream = SpeechRecognitionStream(recognizer: recognizer)
        self.stream = stream
        stream.phrases = { [weak self] in self?.contextualPhrases ?? [] }
        stream.onText = { [weak self] snapshot, final in self?.onText?(snapshot, final) }
        stream.onFailure = { [weak self] message in self?.fail(message) }
        let engine = AVAudioEngine()
        self.engine = engine
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            fail("利用できるマイク入力がありません。Macの入力デバイスを確認してください。"); return
        }
        let audio = stream.audio
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in audio.append(buffer) }
        tapInstalled = true
        do {
            // Capture starts first. The relay retains any opening buffers until
            // the initial request is attached, just as it does during rollover.
            engine.prepare(); try engine.start()
            stream.start()
            onStarted?()
            onStatus?("マイクで聴いています。音声はこのMac内で認識します。")
        } catch { fail("マイクを開始できませんでした：\(error.localizedDescription)") }
    }

    private func fail(_ message: String) { stop(notify: false); onStatus?(message); onStopped?() }

    func stop(notify: Bool = true) {
        generation += 1
        stream?.stop(); stream = nil
        // Recognition rollover never reaches this hardware teardown.
        if let engine {
            engine.stop()
            if tapInstalled { engine.inputNode.removeTap(onBus: 0) }
        }
        engine = nil; tapInstalled = false
        if notify { onStatus?("マイクを停止しました。"); onStopped?() }
    }
}
