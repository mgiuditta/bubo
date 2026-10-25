import AVFoundation
import Observation
import os

/// The Suggeritore: while it is open it follows the meeting Wispr Flow records, transcribes it on the Mac and, at a
/// question about the past, answers in a few words from the Secondo cervello, with the notes cited.
///
/// Only the question and the fragments the Indice finds go to Claude, with the light model; the audio and the
/// trascrizione stay on the Mac.
@Observable
final class MeetingPrompter {
    /// Where the Suggeritore is.
    enum Status: Equatable {
        /// Closed, or open with Wispr Flow not recording.
        case waiting
        /// Hearing the meeting Wispr Flow records.
        case listening
        /// The meeting cannot be transcribed, for `failure`.
        case failed(MeetingFailure)
    }

    /// The sentences of the last ``transcriptWindow``, oldest first.
    private(set) var transcript: [MeetingLine] = []
    /// The answers, newest first, at most ``cardLimit``.
    private(set) var cards: [PromptCard] = []
    private(set) var status = Status.waiting
    /// The Orb of the Suggeritore's window, apart from the Panel's.
    let orb = OrbControls()

    /// Opens the window; set at launch.
    @ObservationIgnored var show: () -> Void = {}

    @ObservationIgnored private var trigger = PromptTrigger()
    @ObservationIgnored private var heardAt: [Date] = []
    @ObservationIgnored private var following: Task<Void, Never>?
    @ObservationIgnored private var answering: Task<Void, Never>?
    @ObservationIgnored private let index: SearchIndex?
    @ObservationIgnored private let bridge: () async throws -> AgentBridge

    /// Creates the Suggeritore.
    ///
    /// - Parameters:
    ///   - index: Where the notes are searched; `nil` when the Indice is unavailable.
    ///   - bridge: The bridge to `claude`, started if needed.
    init(index: SearchIndex?, bridge: @escaping () async throws -> AgentBridge) {
        self.index = index
        self.bridge = bridge
    }

    /// Opens the window and follows Wispr Flow's recordings until ``close()``.
    func open() {
        show()
        guard following == nil else { return }
        orb.state = .idle
        following = Task { await follow() }
    }

    /// Stops following Wispr Flow; the answers stay for the next time the window opens.
    func close() {
        following?.cancel()
        following = nil
    }

    /// Hears a finished sentence, and answers it when it asks about the past.
    func hear(_ line: MeetingLine) {
        let now = Date.now
        let kept = heardAt.firstIndex { now.timeIntervalSince($0) < Self.transcriptWindow } ?? heardAt.count
        transcript = Array(transcript.dropFirst(kept)) + [line]
        heardAt = Array(heardAt.dropFirst(kept)) + [now]
        if let question = trigger.question(in: line, at: now) { answer(question) }
    }

    /// Answers the last question heard in the last minute.
    func answerLastQuestion() {
        if let question = trigger.lastQuestion(at: .now) { answer(question) }
    }

    /// Answers what the user wrote.
    func answer(typed text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        answer(PromptTrigger.Question(text: text, reason: .typed))
    }

    /// Follows the recording Wispr Flow is making, and the next one when it starts, until cancelled.
    private func follow() async {
        var recording: WisprRecording?
        var transcribers: [MeetingLine.Speaker: LiveTranscriber] = [:]
        var feeds: [MeetingLine.Speaker: @Sendable (AVAudioPCMBuffer) -> Void] = [:]
        var ends: [MeetingLine.Speaker: SpeechEndDetector] = [:]
        var heard: [MeetingLine.Speaker: Int] = [:]
        while !Task.isCancelled {
            let folder = WisprRecording.current()
            if folder != recording?.folder {
                for transcriber in transcribers.values { await transcriber.stop() }
                transcribers = [:]
                feeds = [:]
                ends = [:]
                heard = [:]
                recording = folder.map(WisprRecording.init(folder:))
                if recording != nil {
                    (transcribers, feeds) = await startTranscribing()
                } else {
                    status = .waiting
                    if answering == nil { orb.state = .idle }
                }
            }
            for (speaker, buffer) in recording?.newAudio() ?? [] {
                guard let feed = feeds[speaker], let samples = buffer.int16ChannelData?[0] else { continue }
                feed(buffer)
                let count = Int(buffer.frameLength)
                heard[speaker, default: 0] += count
                // At the end of a sentence its text comes at once, as in `sbu-live`, not seconds later.
                if ends[speaker, default: SpeechEndDetector()].hearsEnd(in: UnsafeBufferPointer(start: samples, count: count)) {
                    // In the middle of the pause: audio the analyzer surely has, so it does not wait for more.
                    let end = Double(heard[speaker] ?? 0) / WisprRecording.format.sampleRate - SpeechEndDetector.silence / 2
                    await transcribers[speaker]?.finishSentence(at: end)
                }
            }
            // ponytail: polled every tenth of a second, as `sbu-live` did; FSEvents if it ever shows in Energy.
            try? await Task.sleep(for: .milliseconds(100))
        }
        for transcriber in transcribers.values { await transcriber.stop() }
        status = .waiting
        if answering == nil { orb.state = .idle }
    }

    /// Starts a transcriber for each speaker of a new recording: the trascrizione and the answers start over.
    private func startTranscribing() async -> ([MeetingLine.Speaker: LiveTranscriber],
                                               [MeetingLine.Speaker: @Sendable (AVAudioPCMBuffer) -> Void]) {
        transcript = []
        heardAt = []
        trigger = PromptTrigger()
        var transcribers: [MeetingLine.Speaker: LiveTranscriber] = [:]
        var feeds: [MeetingLine.Speaker: @Sendable (AVAudioPCMBuffer) -> Void] = [:]
        do throws(MeetingFailure) {
            for speaker in [MeetingLine.Speaker.me, .others] {
                let transcriber = LiveTranscriber(speaker: speaker)
                transcribers[speaker] = transcriber
                try await transcriber.start { [weak self] line in self?.hear(line) }
                feeds[speaker] = transcriber.feed(from: WisprRecording.format)
            }
        } catch {
            Logger.meetings.error("Suggeritore not transcribing: \(String(describing: error), privacy: .public)")
            for transcriber in transcribers.values { await transcriber.stop() }
            status = .failed(error)
            return ([:], [:])
        }
        status = .listening
        if answering == nil { orb.state = .listening }
        return (transcribers, feeds)
    }

    /// Searches the notes and streams Claude's answer into a new card; a newer question replaces one still answering.
    private func answer(_ question: PromptTrigger.Question) {
        answering?.cancel()
        let card = PromptCard(question: question.text, reason: question.reason)
        cards = Array(([card] + cards).prefix(Self.cardLimit))
        orb.state = .thinking
        answering = Task {
            let context = await index?.toolResult(for: question.text, project: nil, source: .secondBrain)
                ?? SearchIndex.noResults
            do {
                let agent = try await bridge()
                let model = ModelRouter.defaultChoice(for: .shortFact).0.alias
                for try await text in agent.summarize(Self.prompt(for: question.text, notes: context), model: model) {
                    try Task.checkCancellation()
                    orb.state = .speaking
                    update(card.id) { $0.answer += text }
                }
            } catch is CancellationError {
                // Replaced by a newer question: its card stays as far as it got.
            } catch {
                Logger.meetings.error("Suggeritore not answered: \(String(describing: error), privacy: .public)")
                update(card.id) { $0.failure = String(localized: "Claude non ha risposto. Riprova tra poco.") }
            }
            update(card.id) { $0.isAnswering = false }
            // A newer question owns the Orb and the task now.
            guard !Task.isCancelled else { return }
            orb.state = status == .listening ? .listening : .idle
            answering = nil
        }
    }

    private func update(_ id: PromptCard.ID, _ change: (inout PromptCard) -> Void) {
        guard let position = cards.firstIndex(where: { $0.id == id }) else { return }
        change(&cards[position])
    }

    /// What Claude reads: the rules of a glance-sized answer, the question and the fragments the Indice found.
    nonisolated static func prompt(for question: String, notes: String) -> String {
        """
        Sei il Suggeritore di Bubo: durante una riunione di lavoro l'utente o i colleghi chiedono di riunioni e \
        decisioni passate, e tu rispondi usando solo le note qui sotto, trovate nel suo Secondo cervello.

        Regole:
        - Al massimo 50 parole, senza elenchi né titoli: l'utente la legge di sfuggita mentre parla.
        - Prima il fatto più recente: una decisione o uno stato nuovo vale sui precedenti.
        - Di' sempre la data della riunione o della nota e, se c'è, chi ha deciso o chi deve fare cosa.
        - Cita una o due note, come indicato dopo i frammenti.
        - Se le note non rispondono, scrivi solo: «Non c'è nelle note.»
        - Rispondi nella lingua della domanda.

        Domanda: \(question)

        Note trovate:

        \(notes)
        """
    }

    /// How long a sentence stays in the window.
    static let transcriptWindow: TimeInterval = 120
    /// The most answers the window keeps.
    static let cardLimit = 5
}
