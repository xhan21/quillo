import SwiftUI
import AppKit
import Translation
import Speech

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var speechLanguage: CaptionLanguage = .japanese
    // The current caption source may also be typed text in any of the four languages.
    @Published var sourceLanguage: CaptionLanguage = .japanese
    @Published var targetLanguage: CaptionLanguage = .english
    @Published private(set) var translationEnabled = true
    // Full current recognition result. Only the viewport is limited to fitting lines.
    @Published private(set) var sourceText = ""
    @Published private(set) var translatedText = ""
    @Published var captionKind = "サンプル字幕"
    @Published var status = "「話して字幕を出す」で、マイク入力と字幕表示を一緒に始めます。"
    @Published var translationStatus = "翻訳するには、最初に言語を準備します。"
    @Published var translationReady = false
    @Published var preparingTranslation = false
    @Published var translationConfiguration: TranslationSession.Configuration?
    @Published private(set) var translationSessionID = UUID()
    @Published private(set) var speechLanguageReady = true
    @Published var isListening = false
    @Published var isStartingMic = false
    @Published var isDemoPlaying = false
    @Published var overlayVisible = false
    @Published var positionLocked = false
    @Published var appearance = CaptionAppearance.load() { didSet { appearance.save() } }
    @Published var historySettings = CaptionHistorySettings.load() { didSet { historySettings.save(); updateAppearance() } }
    @Published private(set) var captionCorrectionEnabled = UserDefaults.standard.bool(forKey: "captionCorrection.v1")
    @Published private(set) var correctionStatus = "オフ · 入力文をそのまま表示します。"
    var historyLabel: String { historySettings.visibleCount == 0 ? "現在の一文" : "現在 ＋ 前の\(historySettings.visibleCount)文" }
    private var currentSourceSentence: String { sourceReading.text.isEmpty ? sourceText : sourceReading.currentText }
    private var currentTranslatedSentence: String { sentenceReading.text.isEmpty ? translatedText : sentenceReading.currentText }
    @Published private(set) var sentenceReading = SentenceCaptionReading()
    @Published private(set) var sourceReading = SentenceCaptionReading()
    @Published var displayMode = CaptionDisplayMode(rawValue: UserDefaults.standard.string(forKey: "captionDisplayMode") ?? "") ?? .bilingual {
        didSet { UserDefaults.standard.set(displayMode.rawValue, forKey: "captionDisplayMode"); updateAppearance() }
    }
    @Published private(set) var translationUpdating = false
    @Published private(set) var liveTranslationFailed = false
    @Published var typedText = ""
    @Published var logs: [TranscriptLine] = []
    @Published var selectedScreen = 0
    @Published var helpVisible = false
    var screens: [NSScreen] { NSScreen.screens }
    var overlay: OverlayController?
    var showControlWindow: (() -> Void)?
    let speech = SpeechCapture()
    let slides = SlideTranslationModel()
    let glossary: GlossaryStore
    private var demoTask: Task<Void, Never>?
    private var micStartTask: Task<Void, Never>?
    private var readingTask: Task<Void, Never>?
    private var speechPhrases = SpeechPhraseSegmenter()
    private var currentIsFinal = false
    private var translationContinuation: AsyncStream<Void>.Continuation?
    private var translationEpoch = 0
    private var contentGeneration = 0
    private var languageState = "ja|en"
    private var mailbox = TranslationMailbox()
    private var currentID: UUID?
    private var revisions: [UUID: Int] = [:]
    private var translatedRevisions: [UUID: Int] = [:]
    private var submitted: [UUID: TranslationJob] = [:]
    private let correctSource: (CaptionCorrectionRequest) async throws -> String
    private var correctionTask: Task<Void, Never>?
    private var correctionEpoch = 0
    private var pendingCorrection: (job: TranslationJob, input: CaptionCorrectionRequest)?
    private var correctionAttempts: [UUID: Int] = [:]
    private var finalInputRevisions: [UUID: Int] = [:]
    private var rawSources: [UUID: String] = [:]
    private var inputRevisions: [UUID: Int] = [:]
    // Translation revisions change again when AI repairs/restores the input.
    private var translationFloors: [UUID: Int] = [:]
    private var replacementTranslations: [UUID: Int] = [:]
    // Internal read-only diagnostics used by the integration tests.
    var pendingTranslationCount: Int { mailbox.count }
    var requiresTranslation: Bool { translationEnabled && sourceLanguage != targetLanguage }
    var convertsChineseScript: Bool { sourceLanguage != targetLanguage && sourceLanguage.isChinese && targetLanguage.isChinese }
    var languagePairLabel: String { "\(sourceLanguage.name) → \(targetLanguage.name)" }
    var visibleCaption: VisibleCaption { captionPresentation.caption }
    var captionPresentation: CaptionPresentation {
        let size = captionLayoutSize
        let showsSource = !requiresTranslation || displayMode == .bilingual
        let budget = max(1, size.height - 76) / (showsSource && requiresTranslation ? 2 : 1)
        let original = showsSource ? SentenceCaptionLayout.layout(text: currentSourceSentence, history: sourceReading.history,
            fontSize: appearance.sourceFontSize, width: size.width - 60, height: budget, language: sourceLanguage, historyLimit: historySettings.visibleCount) : nil
        let waiting = liveTranslationFailed ? "翻訳を再準備してください" : nil
        var reading: SentenceCaptionLayout?
        if requiresTranslation && SentenceCaptionLayout.supports(targetLanguage) {
            reading = SentenceCaptionLayout.layout(text: currentTranslatedSentence,
                history: sentenceReading.history, fontSize: appearance.translationFontSize, width: size.width - 60,
                height: budget, language: targetLanguage, historyLimit: historySettings.visibleCount)
        }
        let translation = reading?.text ?? ""
        // A retained previous sentence has its own dimmed block. Its header says
        // that the next translation is pending; do not overlap it with a placeholder.
        let placeholder = reading?.previous.isEmpty == false ? "" : waiting ?? (requiresTranslation && !sourceText.isEmpty && translation.isEmpty ? (translationReady ? "翻訳しています…" : "翻訳を準備してください") : nil)
        let caption = VisibleCaption(source: original?.text ?? "", translation: translation, translates: requiresTranslation,
            mode: displayMode, ready: translationReady, waiting: placeholder)
        return CaptionPresentation(caption: caption, reading: reading, sourceReading: original)
    }
    var liveLabel: String {
        if isDemoPlaying { return "ライブ表示のデモ" }
        if requiresTranslation && liveTranslationFailed { return "翻訳を再準備" }
        if translationUpdating { return translationReady ? "翻訳を更新中…" : "翻訳を準備中…" }
        return isListening ? "ライブ更新" : "ライブ字幕"
    }
    // Source correction works even in original-only mode, before translation.
    var currentCorrectionState: CaptionCorrectionState? {
        guard !sourceText.isEmpty, !isDemoPlaying else { return nil }
        return logs.last(where: { $0.id == currentID })?.correctionState
    }
    var latestCorrection: TranscriptLine? {
        logs.last { $0.sourceCorrected && $0.sourceBeforeCorrection != nil }
    }
    var minimumPanelHeight: Double {
        let source = !requiresTranslation || displayMode == .bilingual
        let block = max(source ? SentenceCaptionLayout.minimumHeight(fontSize: appearance.sourceFontSize, historyLimit: historySettings.visibleCount) : 0,
                        requiresTranslation ? SentenceCaptionLayout.minimumHeight(fontSize: appearance.translationFontSize, historyLimit: historySettings.visibleCount) : 0)
        let total = 76 + block * (source && requiresTranslation ? 2 : 1)
        return max(110, ceil(total / 10) * 10)
    }
    var captionLayoutSize: NSSize {
        let screen = overlay?.panel.screen ?? NSScreen.main
        let visible = screen?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
        let source = !requiresTranslation || displayMode == .bilingual
        let width = min(appearance.width, visible.width - 24)
        let original = source ? SentenceCaptionLayout.preferredHeight(text: currentSourceSentence, history: sourceReading.history,
            fontSize: appearance.sourceFontSize, width: width - 60, language: sourceLanguage, historyLimit: historySettings.visibleCount) : 0
        let translated = requiresTranslation ? SentenceCaptionLayout.preferredHeight(text: currentTranslatedSentence,
            history: sentenceReading.history, fontSize: appearance.translationFontSize, width: width - 60, language: targetLanguage, historyLimit: historySettings.visibleCount) : 0
        let natural = 76 + max(original, translated) * (source && requiresTranslation ? 2 : 1)
        let height = appearance.automaticHeight ? min(natural, max(minimumPanelHeight, visible.height * 0.6)) : appearance.height
        return NSSize(width: min(appearance.width, visible.width - 24), height: min(visible.height - 24, max(minimumPanelHeight, height)))
    }

    init(glossary: GlossaryStore? = nil, corrector: ((CaptionCorrectionRequest) async throws -> String)? = nil) {
        let client = LocalCaptionCorrector()
        correctSource = corrector ?? { try await client.correct($0) }
        self.glossary = glossary ?? GlossaryStore()
        self.glossary.onChange = { [weak self] in self?.glossaryChanged() }
        speech.contextualPhrases = self.glossary.selected?.recognitionPhrases(sourceLanguage) ?? []
        slides.setGlossary(self.glossary.selected)
        speech.onText = { [weak self] snapshot, final in self?.handleSpeech(snapshot, final: final) }
        speech.onStatus = { [weak self] message in self?.status = message }
        speech.onStarted = { [weak self] in self?.isStartingMic = false }
        speech.onStopped = { [weak self] in self?.isListening = false; self?.isStartingMic = false }
        showSample()
        if captionCorrectionEnabled { correctionStatus = "オン · 話の区切りで入力文を補正します。" }
        refreshSpeechReadiness()
    }
    func refreshSpeechReadiness() {
        speechLanguageReady = SFSpeechRecognizer(locale: Locale(identifier: speechLanguage.speechLocale))?.supportsOnDeviceRecognition == true
    }
    func setSpeechLanguage(_ language: CaptionLanguage) {
        guard language.supportsSpeechInput else { return }
        speechLanguage = language
        useSpeechLanguageForCaptions()
        refreshSpeechReadiness()
    }
    func useSpeechLanguageForCaptions() {
        guard sourceLanguage != speechLanguage else { return }
        sourceLanguage = speechLanguage
        languageChanged()
    }
    private func glossaryChanged() {
        let raw = currentID.flatMap { rawSources[$0] } ?? sourceText
        resetCorrections()
        readingTask?.cancel(); readingTask = nil; sentenceReading = SentenceCaptionReading()
        if let currentID { sentenceReading.begin(currentID, language: targetLanguage, now: ProcessInfo.processInfo.systemUptime) }
        speech.contextualPhrases = glossary.selected?.recognitionPhrases(sourceLanguage) ?? []
        slides.setGlossary(glossary.selected)
        // Invalidate old dictionary work without restarting capture/session.
        contentGeneration += 1; mailbox.removeAll(); submitted.removeAll()
        revisions.removeAll(); translatedRevisions.removeAll(); inputRevisions.removeAll(); rawSources.removeAll()
        translationFloors.removeAll(); replacementTranslations.removeAll()
        guard let id = currentID else { return }
        revisions[id] = 1; inputRevisions[id] = 1; rawSources[id] = raw
        sourceText = raw; translatedText = ""; translationUpdating = requiresTranslation
        sourceReading.replace(raw, cueID: id, now: ProcessInfo.processInfo.systemUptime)
        if currentIsFinal { finalInputRevisions[id] = 1 }
        if let index = logs.firstIndex(where: { $0.id == id }) {
            logs[index].source = raw; logs[index].sourceBeforeCorrection = nil; logs[index].correctionState = .original
            logs[index].translation = ""; logs[index].translationIncomplete = requiresTranslation
        }
        if requiresTranslation { submitTranslation(id: id, text: raw) }
        if currentIsFinal { requestCorrection(id) }
    }
    var microphoneActionTitle: String { isStartingMic ? "開始を中止" : isListening ? "字幕を停止" : "話して字幕を出す" }
    func hideOverlay() { overlayVisible = false; overlay?.hide() }
    func toggleOverlay() {
        if overlayVisible { hideOverlay() }
        else if isListening || isStartingMic { ensureOverlay() }
        else { toggleMic() }
    }
    func ensureOverlay() { if !overlayVisible { overlayVisible = true; overlay?.show() } }
    func toggleLock() { positionLocked.toggle(); overlay?.updateInteraction() }
    func updateAppearance() {
        // The effective minimum grows for history, without overwriting saved sizes.
        let bounded = appearance.normalized()
        if appearance != bounded { appearance = bounded }
        overlay?.refreshSize()
    }
    private func scheduleReadingUpdate() {
        readingTask?.cancel(); readingTask = nil
        guard let deadline = sentenceReading.nextWakeup else { return }
        readingTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(max(0.01, deadline - ProcessInfo.processInfo.systemUptime)))
            guard !Task.isCancelled, let self else { return }
            self.sentenceReading.tick(now: ProcessInfo.processInfo.systemUptime)
            self.scheduleReadingUpdate()
        }
    }
    private func resetLiveCaption() {
        resetCorrections()
        readingTask?.cancel(); readingTask = nil; sentenceReading = SentenceCaptionReading(); sourceReading = SentenceCaptionReading(); speechPhrases = SpeechPhraseSegmenter(); currentIsFinal = false
        contentGeneration += 1; mailbox.removeAll(); revisions.removeAll(); translatedRevisions.removeAll(); submitted.removeAll()
        rawSources.removeAll(); inputRevisions.removeAll(); translationFloors.removeAll(); replacementTranslations.removeAll()
        currentID = nil; sourceText = ""; translatedText = ""; translationUpdating = false; liveTranslationFailed = false
    }
    private func showSample() {
        let sample = SampleCaption.examples[0]
        sourceText = sample.text(sourceLanguage); translatedText = sample.text(targetLanguage); captionKind = "サンプル字幕"
    }

    // Every partial result reaches the original caption synchronously. No silence
    // timer, translation completion, or reading-duration timer gates this path.
    private func receive(_ text: String, id: UUID, kind: String, final: Bool = false) {
        let clean = sourceLanguage.normalizeScript(captionText(text))
        guard !clean.isEmpty else { return }
        let index = logs.firstIndex { $0.id == id }
        let changed = rawSources[id] != clean
        let wasCorrected = index.map { logs[$0].sourceCorrected } ?? false
        if currentID != id {
            sentenceReading.begin(id, language: targetLanguage, now: ProcessInfo.processInfo.systemUptime); scheduleReadingUpdate()
            sourceReading.begin(id, language: sourceLanguage, now: ProcessInfo.processInfo.systemUptime)
            currentID = id; translatedText = ""; liveTranslationFailed = false
        }
        currentIsFinal = final
        // A duplicate ASR callback must not revert an already corrected input.
        let displayed = !changed ? index.map { logs[$0].source } ?? clean : clean
        sourceText = displayed; captionKind = kind; mailbox.preferredID = id
        if changed && wasCorrected { sourceReading.replace(displayed, cueID: id, now: ProcessInfo.processInfo.systemUptime) }
        else { sourceReading.receive(displayed, now: ProcessInfo.processInfo.systemUptime, final: true) }
        if let index {
            logs[index].source = displayed
            if changed { logs[index].translationIncomplete = requiresTranslation }
        } else {
            logs.append(TranscriptLine(id: id, time: Date(), source: clean, translation: "", kind: kind == "文字入力" ? "入力" : "音声", translationIncomplete: requiresTranslation))
        }
        if changed {
            rawSources[id] = clean; inputRevisions[id, default: 0] += 1
            revisions[id, default: 0] += 1; liveTranslationFailed = false
            finalInputRevisions[id] = nil
            if let index { logs[index].correctionState = .original; logs[index].sourceBeforeCorrection = nil }
            if wasCorrected { invalidateTranslation(id) }
        }
        if final { finalInputRevisions[id] = inputRevisions[id] }
        translationUpdating = requiresTranslation && translatedRevisions[id] != revisions[id]
        if requiresTranslation { submitTranslation(id: id, text: displayed) }
        if final {
            sentenceReading.flush(now: ProcessInfo.processInfo.systemUptime); scheduleReadingUpdate()
            requestCorrection(id)
        }
    }
    private func handleSpeech(_ snapshot: SpeechSnapshot, final: Bool) {
        guard isListening || isStartingMic else { return }
        isStartingMic = false
        for update in speechPhrases.receive(snapshot, final: final, now: ProcessInfo.processInfo.systemUptime, language: sourceLanguage) {
            receive(update.snapshot.text, id: update.snapshot.segmentID, kind: "マイク字幕", final: update.final)
        }
    }
    private func submitTranslation(id: UUID, text: String) {
        guard let revision = revisions[id] else { return }
        let job = TranslationJob(cueID: id, revision: revision, generation: contentGeneration, text: text)
        guard submitted[id] != job else { return }
        submitted[id] = job
        if convertsChineseScript {
            acceptTranslation(targetLanguage.normalizeScript(text), for: job)
            translationReady = true
            return
        }
        mailbox.submit(job); translationContinuation?.yield(())
    }

    // nil selects original-only. A display change must never reset capture, the
    // current utterance, or a prepared/in-flight translation session.
    func setCaptionMode(_ mode: CaptionDisplayMode?) {
        translationEnabled = mode != nil
        if let mode { displayMode = mode }
        updateAppearance()
        translationUpdating = requiresTranslation && currentID.map { translatedRevisions[$0] != revisions[$0] } == true
        guard requiresTranslation else {
            translationStatus = "原文のみを表示しています。翻訳を表示するには「翻訳のみ」か「原文 ＋ 翻訳」を選んでください。"
            return
        }
        if translationUpdating, let id = currentID {
            if let index = logs.firstIndex(where: { $0.id == id }) { logs[index].translationIncomplete = true }
            submitTranslation(id: id, text: sourceText)
        }
        // Corrections made while original-only also need translations in their
        // own retained history slots when translated display is restored.
        for line in logs.suffix(3) where inputRevisions[line.id] != nil && translatedRevisions[line.id] != revisions[line.id] {
            submitTranslation(id: line.id, text: line.source)
        }
        // Original-only may have started before a session existed. Resume from
        // the current text even if the speaker has already stopped talking.
        if !translationReady || liveTranslationFailed { prepareTranslation() }
        else {
            translationStatus = convertsChineseScript
                ? "\(languagePairLabel) · このMac内で字体を変換します。"
                : "\(languagePairLabel) · 翻訳の準備ができました。"
        }
    }

    func languageChanged() {
        let state = "\(sourceLanguage.rawValue)|\(targetLanguage.rawValue)"
        guard state != languageState else { return }
        languageState = state
        // Only the output language is shared. A spoken/typed source change must
        // not change OCR language or stop the selected material capture.
        slides.configure(source: slides.source, target: targetLanguage)
        stopMic(); stopDemo(); resetLiveCaption()
        speech.contextualPhrases = glossary.selected?.recognitionPhrases(sourceLanguage) ?? []
        translationEpoch += 1; translationContinuation?.finish(); translationContinuation = nil
        translationConfiguration = nil; translationReady = false; preparingTranslation = false
        translationSessionID = UUID()
        translationStatus = requiresTranslation ? "言語を変更しました。「翻訳を準備」を押してください。" : "原文字幕のみ表示します。"
        captionKind = "字幕待機中"; updateAppearance(); refreshSpeechReadiness()
        if requiresTranslation { prepareTranslation() }
    }
    func prepareTranslation() {
        guard requiresTranslation, !preparingTranslation else { return }
        translationEpoch += 1; translationContinuation?.finish(); translationContinuation = nil
        submitted.removeAll()
        // Retry incomplete final transcript translations as well as the live text.
        for line in logs where revisions[line.id] != nil && line.translationIncomplete {
            submitTranslation(id: line.id, text: line.source)
        }
        liveTranslationFailed = false
        if convertsChineseScript {
            translationConfiguration = nil; translationReady = true; preparingTranslation = false
            translationStatus = "\(languagePairLabel) · このMac内で字体を変換します。"
            return
        }
        preparingTranslation = true; translationReady = false
        translationStatus = "\(languagePairLabel) を準備しています。初回はmacOSの言語データ取得を確認してください。"
        // Give every language change/retry its own SwiftUI translation host.
        // Reusing a cancelled host can leave macOS 15 stuck before the action runs.
        translationConfiguration = TranslationSession.Configuration(source: Locale.Language(identifier: sourceLanguage.rawValue), target: Locale.Language(identifier: targetLanguage.rawValue))
        translationSessionID = UUID()
    }
    func retryTranslation() {
        preparingTranslation = false
        prepareTranslation()
    }
    func runTranslation(_ session: TranslationSession, sessionID: UUID) async {
        guard sessionID == translationSessionID, !Task.isCancelled else { return }
        let epoch = translationEpoch
        let source = sourceLanguage, target = targetLanguage
        await runTranslationWorker(expectedEpoch: epoch, prepare: {
            let availability = await LanguageAvailability().status(from: Locale.Language(identifier: source.rawValue), to: Locale.Language(identifier: target.rawValue))
            guard availability != .unsupported else { throw TranslationError.unsupportedLanguagePairing }
            try await session.prepareTranslation()
        }, translate: { try await session.translate($0).targetText })
    }
    // Shared production/test worker: one translation in flight, one latest pending
    // hypothesis per utterance. Wakeups are bounded too, so speech cannot flood it.
    func runTranslationWorker(expectedEpoch: Int? = nil, prepare: () async throws -> Void, translate: (String) async throws -> String) async {
        let epoch = expectedEpoch ?? translationEpoch
        guard epoch == translationEpoch, !Task.isCancelled else { return }
        let stream = AsyncStream<Void>(bufferingPolicy: .bufferingNewest(1)) { translationContinuation = $0 }
        defer {
            if epoch == translationEpoch {
                translationContinuation?.finish(); translationContinuation = nil
                translationReady = false; preparingTranslation = false
            }
        }
        do {
            try await prepare()
            guard epoch == translationEpoch, !Task.isCancelled else { return }
            preparingTranslation = false; translationReady = true
            translationStatus = "\(languagePairLabel) · 翻訳の準備ができました。"
            translationContinuation?.yield(())
            var lastStart: ContinuousClock.Instant?
            for await _ in stream {
                while !mailbox.isEmpty {
                    guard epoch == translationEpoch, !Task.isCancelled else { return }
                    // Rate limit starts, not recognition updates. A continuous
                    // stream of speech cannot postpone translation indefinitely.
                    if let lastStart {
                        try await Task.sleep(until: lastStart.advanced(by: .milliseconds(180)), clock: .continuous)
                    }
                    guard epoch == translationEpoch, !Task.isCancelled else { return }
                    guard let job = mailbox.takeNext() else { break }
                    lastStart = .now
                    do {
                        let terminology = GlossaryTranslation(source: job.text, language: sourceLanguage, target: targetLanguage, glossary: glossary.selected)
                        let translated = try await terminology.translate(using: translate)
                        guard epoch == translationEpoch, !Task.isCancelled else { return }
                        guard job.generation == contentGeneration else { continue }
                        guard !captionText(translated).isEmpty else { throw NSError(domain: "KotobaTranslation", code: 1) }
                        acceptTranslation(targetLanguage.normalizeScript(translated), for: job)
                    } catch {
                        guard epoch == translationEpoch, !Task.isCancelled else { return }
                        guard job.generation == contentGeneration else { continue }
                        if currentID == job.cueID && revisions[job.cueID] == job.revision {
                            liveTranslationFailed = true; translationUpdating = false
                        }
                        translationStatus = "翻訳できない文章がありました。字幕の更新は続けます。「翻訳を準備」で再試行できます。"
                    }
                }
            }
        } catch {
            guard epoch == translationEpoch, !Task.isCancelled else { return }
            translationReady = false; preparingTranslation = false
            liveTranslationFailed = true
            translationStatus = TranslationError.unsupportedLanguagePairing ~= error
                ? "\(languagePairLabel) は、このmacOSの翻訳機能で利用できません。"
                : "\(languagePairLabel) を準備できませんでした。「翻訳を準備」で再試行し、macOSの言語データ取得を確認してください。"
        }
    }
    private func acceptTranslation(_ text: String, for job: TranslationJob) {
        guard job.revision >= translationFloors[job.cueID, default: 0],
              job.revision > translatedRevisions[job.cueID, default: 0] else { return }
        translatedRevisions[job.cueID] = job.revision
        let incomplete = revisions[job.cueID] != job.revision
        if let index = logs.firstIndex(where: { $0.id == job.cueID }) {
            logs[index].translation = text; logs[index].translationIncomplete = incomplete
        }
        if replacementTranslations[job.cueID] == job.revision {
            sentenceReading.replace(text, cueID: job.cueID, now: ProcessInfo.processInfo.systemUptime)
        } else {
            sentenceReading.receive(text, now: ProcessInfo.processInfo.systemUptime,
                final: currentIsFinal && !incomplete, cueID: job.cueID,
                sourcePosition: max(0, SentenceCaptionLayout.sentences(job.text, language: sourceLanguage).count - 1))
        }
        guard currentID == job.cueID else { return }
        translatedText = text; translationUpdating = requiresTranslation && incomplete; liveTranslationFailed = false
        scheduleReadingUpdate()
    }

    // Hide an obsolete translation while the repaired/restored source is being
    // translated. Retain cue identity so this never becomes an extra utterance.
    private func invalidateTranslation(_ id: UUID) {
        translationFloors[id] = revisions[id]; replacementTranslations[id] = revisions[id]
        sentenceReading.invalidate(cueID: id)
        if let index = logs.firstIndex(where: { $0.id == id }) {
            logs[index].translation = ""; logs[index].translationIncomplete = sourceLanguage != targetLanguage
        }
        if currentID == id {
            translatedText = ""; translationUpdating = requiresTranslation; liveTranslationFailed = false
        }
    }
    private func replaceSource(_ text: String, id: UUID) {
        guard let index = logs.firstIndex(where: { $0.id == id }) else { return }
        logs[index].source = text
        sourceReading.replace(text, cueID: id, now: ProcessInfo.processInfo.systemUptime)
        if currentID == id { sourceText = text }
        revisions[id, default: 0] += 1
        invalidateTranslation(id)
        if requiresTranslation { submitTranslation(id: id, text: text) }
        scheduleReadingUpdate()
    }
    func setCaptionCorrection(_ enabled: Bool) {
        guard captionCorrectionEnabled != enabled else { return }
        captionCorrectionEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "captionCorrection.v1")
        correctionEpoch += 1; correctionTask?.cancel(); correctionTask = nil; pendingCorrection = nil; correctionAttempts = [:]
        clearPendingCorrectionStates()
        correctionStatus = enabled ? "オン · 話の区切りで入力文を補正します。" : "オフ · 入力文をそのまま表示します。"
        if enabled {
            if let currentID { requestCorrection(currentID) }
        } else {
            // Restore the captured input, then translate it again; never restore
            // a translation of a different source or restart microphone capture.
            for index in logs.indices.suffix(3) where logs[index].sourceCorrected {
                let id = logs[index].id
                guard let raw = rawSources[id], inputRevisions[id] != nil else { continue }
                logs[index].correctionState = .original; logs[index].sourceBeforeCorrection = nil
                replaceSource(raw, id: id)
            }
        }
    }
    private func resetCorrections() {
        correctionEpoch += 1; correctionTask?.cancel(); correctionTask = nil; pendingCorrection = nil
        clearPendingCorrectionStates()
        correctionAttempts = [:]; finalInputRevisions = [:]
        correctionStatus = captionCorrectionEnabled ? "オン · 話の区切りで入力文を補正します。" : "オフ · 入力文をそのまま表示します。"
    }
    private func clearPendingCorrectionStates() {
        for index in logs.indices where [.queued, .checking, .unchanged, .unavailable].contains(logs[index].correctionState) {
            logs[index].correctionState = .original
        }
    }
    private func setCorrectionState(_ state: CaptionCorrectionState, for job: TranslationJob) {
        guard job.generation == contentGeneration, inputRevisions[job.cueID] == job.revision,
              let index = logs.firstIndex(where: { $0.id == job.cueID }) else { return }
        logs[index].correctionState = state
    }
    private func requestCorrection(_ id: UUID) {
        guard captionCorrectionEnabled, let raw = rawSources[id], let revision = inputRevisions[id],
              finalInputRevisions[id] == revision, correctionAttempts[id] != revision,
              let index = logs.firstIndex(where: { $0.id == id }), index >= logs.count - 3 else { return }
        correctionAttempts[id] = revision
        let job = TranslationJob(cueID: id, revision: revision, generation: contentGeneration, text: raw)
        let previous = index > 0 && rawSources[logs[index - 1].id] != nil ? logs[index - 1].source : ""
        let input = CaptionCorrectionRequest(source: raw, language: sourceLanguage, previousSource: previous,
            terminology: glossary.selected?.summaryTerms(in: raw, language: sourceLanguage, target: sourceLanguage) ?? "")
        if let pendingCorrection, let pendingIndex = logs.firstIndex(where: { $0.id == pendingCorrection.job.cueID }), pendingIndex > index { return }
        if let old = pendingCorrection { setCorrectionState(.original, for: old.job) }
        pendingCorrection = (job, input); setCorrectionState(.queued, for: job)
        guard correctionTask == nil else { return }
        let epoch = correctionEpoch
        correctionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if epoch == self.correctionEpoch {
                    self.correctionTask = nil
                    if self.correctionStatus.hasPrefix("入力文を補正中") { self.correctionStatus = "オン · 次の話の区切りを待っています。" }
                }
            }
            while let pending = self.pendingCorrection {
                self.pendingCorrection = nil
                guard !Task.isCancelled, epoch == self.correctionEpoch else { return }
                guard self.canApplyCorrection(pending.job) else {
                    self.setCorrectionState(.original, for: pending.job); continue
                }
                self.setCorrectionState(.checking, for: pending.job)
                self.correctionStatus = "入力文を補正中 · 字幕の表示は続けます。"
                do {
                    let value = try await self.correctSource(pending.input)
                    guard !Task.isCancelled, epoch == self.correctionEpoch else { return }
                    guard self.canApplyCorrection(pending.job) else {
                        self.setCorrectionState(.original, for: pending.job); continue
                    }
                    let text = try LocalCaptionCorrector.validate(value, for: pending.input)
                    let changed = text != pending.input.source
                    if let index = self.logs.firstIndex(where: { $0.id == pending.job.cueID }) {
                        self.logs[index].correctionState = changed ? .corrected : .unchanged
                        self.logs[index].sourceBeforeCorrection = changed ? pending.input.source : nil
                    }
                    if changed { self.replaceSource(text, id: pending.job.cueID) }
                    self.correctionStatus = changed ? "補正済み · 補正した入力文を翻訳に使います。" : "確認済み · 入力文をそのまま使います。"
                } catch {
                    guard !Task.isCancelled, epoch == self.correctionEpoch else { return }
                    self.setCorrectionState(.unavailable, for: pending.job)
                    self.correctionStatus = "入力文をそのまま表示中 · AIが遅い、未準備、または補正を採用できませんでした。"
                }
            }
        }
    }
    private func canApplyCorrection(_ job: TranslationJob) -> Bool {
        captionCorrectionEnabled && job.generation == contentGeneration && inputRevisions[job.cueID] == job.revision
            && finalInputRevisions[job.cueID] == job.revision && rawSources[job.cueID] == job.text
            && logs.suffix(3).contains(where: { $0.id == job.cueID })
    }

    func toggleMic() {
        if isListening || isStartingMic { stopMic(); return }
        useSpeechLanguageForCaptions()
        refreshSpeechReadiness()
        guard speechLanguageReady else {
            status = "\(speechLanguage.dictationName)の端末内音声認識を利用できません。Macの「システム設定 → キーボード → 音声入力 → 言語」を確認してください。"
            return
        }
        stopDemo(); resetLiveCaption()
        isStartingMic = true; isListening = true; captionKind = "マイク準備中"
        status = "マイクと音声認識の許可を確認しています。"; ensureOverlay()
        if requiresTranslation && !translationReady { prepareTranslation() }
        let language = speechLanguage
        micStartTask = Task { await speech.start(language: language) }
    }
    func stopMic() {
        let wasActive = isListening || isStartingMic
        micStartTask?.cancel(); micStartTask = nil
        speech.stop(notify: wasActive)
        isListening = false; isStartingMic = false
        if wasActive, let currentID {
            currentIsFinal = true; finalInputRevisions[currentID] = inputRevisions[currentID]; requestCorrection(currentID)
        }
        if wasActive { status = "マイクを停止しました。最後の発話の翻訳は更新を続けます。" }
    }
    func sendTypedCaption() {
        let text = captionText(typedText)
        guard !text.isEmpty else { return }
        stopMic(); stopDemo()
        receive(text, id: UUID(), kind: "文字入力", final: true)
        if requiresTranslation && !translationReady { prepareTranslation() }
        typedText = ""; ensureOverlay()
        status = "入力した原文をすぐ表示しました。全文は字幕ログに保持します。"
    }
    func toggleDemo() {
        if isDemoPlaying { stopDemo(); return }
        stopMic(); resetLiveCaption(); isDemoPlaying = true; ensureOverlay()
        status = "話の途中で字幕が伸びる表示デモです。準備済みの文章を使い、マイクは使用しません。"
        demoTask = Task<Void, Never> { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                for sample in SampleCaption.examples {
                    let original = Array(sample.text(self.sourceLanguage))
                    let translated = Array(sample.text(self.targetLanguage))
                    self.captionKind = "サンプル字幕"; self.sourceText = ""; self.translatedText = ""
                    for count in 1...original.count {
                        guard !Task.isCancelled else { return }
                        self.sourceText = String(original.prefix(count))
                        let progress = Double(max(0, count - 2)) / Double(original.count)
                        let translatedCount = Int(progress * Double(translated.count))
                        self.translatedText = String(translated.prefix(translatedCount))
                        try? await Task.sleep(for: .milliseconds(140))
                    }
                    guard !Task.isCancelled else { return }
                    self.translatedText = String(translated)
                    try? await Task.sleep(for: .milliseconds(700))
                }
            }
        }
    }
    func stopDemo() {
        guard isDemoPlaying else { return }
        isDemoPlaying = false; demoTask?.cancel(); demoTask = nil; status = "デモを停止しました。"
    }
    func clearCaption() { stopMic(); stopDemo(); resetLiveCaption(); captionKind = "字幕待機中"; overlay?.refreshSize() }
    func exportTranscript() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.plainText]; panel.nameFieldStringValue = "Quillo-字幕ログ.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let formatter = DateFormatter(); formatter.dateFormat = "HH:mm:ss"
        let entries = logs.map { line -> String in
            var parts = ["[\(formatter.string(from: line.time))] \(line.kind)", line.source, line.translation]
            if let before = line.sourceBeforeCorrection { parts.append("（原文をAI補正・補正前：" + before + "）") }
            if line.translationIncomplete { parts.append("（翻訳未完了・途中の結果）") }
            return parts.joined(separator: "\n")
        }
        let text = "Quillo · 字幕ログ\n翻訳未完了の行には印を付けています。\n\n" + entries.joined(separator: "\n\n")
        do { try text.write(to: url, atomically: true, encoding: .utf8); status = "字幕ログを保存しました。" } catch { status = "保存できませんでした：\(error.localizedDescription)" }
    }
    func shutdown() { stopMic(); resetCorrections(); slides.shutdown(); stopDemo(); readingTask?.cancel(); readingTask = nil; translationContinuation?.finish(); overlay?.savePosition() }
}
