import AppKit
import Observation
import os

/// Records a Riunione on two tracks, the microphone and the audio of an app, then transcribes it on the Mac, has the
/// summary engine write what was decided, and saves the note in `Bubo/Riunioni/`, where the Indice finds it.
@Observable
final class MeetingRecorder {
    /// Where a Riunione is.
    enum Phase: Equatable {
        /// Nothing recorded since launch.
        case idle
        /// Recording since `start`.
        case recording(Recording)
        /// Stopped: transcribing, summarizing and writing the note.
        case processing
        /// The note was written at `file`.
        case saved(file: URL)
        /// Not recorded or not saved, for `failure`.
        case failed(MeetingFailure)
    }

    /// A Riunione being recorded.
    struct Recording: Equatable {
        var title: String
        /// The app whose audio is recorded; `nil` with the microphone only.
        var app: MeetingApp?
        var start: Date
        /// The folder of its tracks, in Application Support.
        var folder: URL
    }

    /// Where the Riunione is now.
    private(set) var phase = Phase.idle

    /// Whether a Riunione is being recorded: the indicator in the menu bar shows meanwhile.
    var isRecording: Bool {
        if case .recording = phase { true } else { false }
    }

    /// Whether the last Riunione failed after the recording with its audio kept, so ``retry()`` can start from it.
    var canRetry: Bool {
        guard case let .failed(failure) = phase else { return false }
        return failure.keepsAudio && unsaved != nil
    }

    /// The Riunione recorded but not saved, with how long it lasted: what ``retry()`` starts from.
    private var unsaved: (recording: Recording, duration: Duration)?

    /// Opens the window of the Riunioni; set at launch.
    @ObservationIgnored var showWindow: () -> Void = {}

    /// The imports of recordings and trascrizioni, summarized as the recorded Riunioni.
    @ObservationIgnored private(set) lazy var imports = MeetingImporter(secondBrain: secondBrain) { [unowned self] transcript in
        await summary(of: transcript)
    } showWindow: { [unowned self] in
        showWindow()
    }

    @ObservationIgnored private let secondBrain: SecondBrain
    @ObservationIgnored private let engines: [any SummaryEngine]
    @ObservationIgnored private let store: MeetingAudioStore?
    @ObservationIgnored private let microphoneAccess: MicrophoneAccess
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let transcribe: Transcription
    @ObservationIgnored private let microphone = MicrophoneTrack()
    @ObservationIgnored private let appAudio = AppAudioTrack()

    /// Creates the recorder.
    ///
    /// - Parameters:
    ///   - secondBrain: Where the notes go.
    ///   - engines: The models that write the summary, tried in order.
    ///   - store: Where the audio goes; `nil` when Application Support is unavailable.
    ///   - transcribe: What turns a track into sentences.
    init(secondBrain: SecondBrain, engines: [any SummaryEngine], store: MeetingAudioStore?,
         microphoneAccess: MicrophoneAccess = .system, defaults: UserDefaults = .standard,
         transcribe: @escaping Transcription = MeetingTranscriber.transcribe) {
        self.secondBrain = secondBrain
        self.engines = engines
        self.store = store
        self.microphoneAccess = microphoneAccess
        self.defaults = defaults
        self.transcribe = transcribe
    }

    /// Deletes the audio past its retention, off the main actor.
    func removeExpiredAudio() async {
        guard let store else { return }
        await Self.removeExpired(in: store)
    }

    /// Starts recording the microphone and, with `app`, the audio of that app.
    func start(titled title: String, app: MeetingApp?) async {
        guard !isRecording, phase != .processing else { return }
        guard secondBrain.location != nil else { return fail(.noSecondBrain) }
        if microphoneAccess.status() == .undetermined { _ = await microphoneAccess.request() }
        guard microphoneAccess.status() == .granted else { return fail(.microphoneDenied) }
        guard let store, let folder = try? store.makeRecordingFolder() else { return fail(.microphoneUnavailable) }
        do throws(MeetingFailure) {
            try microphone.start(writingTo: folder.appending(path: Self.myTrack))
            if let app {
                let processes = AudioProcesses.objects(ofApp: app.bundleID)
                guard !processes.isEmpty else { throw .appSilent(app.name) }
                try appAudio.start(processes: processes, writingTo: folder.appending(path: Self.othersTrack))
            }
        } catch {
            microphone.stop()
            store.remove(folder)
            return fail(error)
        }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        phase = .recording(Recording(title: name.isEmpty ? String(localized: "Riunione") : name, app: app,
                                     start: .now, folder: folder))
        Logger.meetings.notice("Riunione recording, app audio \(app != nil, privacy: .public)")
        announce(String(localized: "Registrazione della Riunione iniziata"))
    }

    /// Stops recording, then transcribes, summarizes and saves the note.
    func stop() async {
        guard case let .recording(recording) = phase else { return }
        microphone.stop()
        appAudio.stop()
        announce(String(localized: "Registrazione fermata. Bubo trascrive la Riunione sul Mac."))
        await process(recording, lasting: .seconds(Date.now.timeIntervalSince(recording.start)))
    }

    /// Transcribes, summarizes and saves again the Riunione that failed, from its kept audio.
    func retry() async {
        guard canRetry, let unsaved else { return }
        announce(String(localized: "Bubo trascrive di nuovo la Riunione sul Mac."))
        await process(unsaved.recording, lasting: unsaved.duration)
    }

    /// Transcribes, summarizes and saves `recording`; kept for ``retry()`` until the note is written.
    func process(_ recording: Recording, lasting duration: Duration) async {
        phase = .processing
        unsaved = (recording, duration)
        do throws(MeetingFailure) {
            let file = try await save(recording, lasting: duration)
            unsaved = nil
            phase = .saved(file: file)
            announce(String(localized: "Riunione salvata nel Secondo cervello"))
        } catch {
            fail(error)
        }
    }

    /// Transcribes both tracks, summarizes them and writes the note; deletes the audio when the user chose so.
    private func save(_ recording: Recording, lasting duration: Duration) async throws(MeetingFailure) -> URL {
        let mine = try await transcribe(recording.folder.appending(path: Self.myTrack), .me)
        let others = recording.app == nil ? []
            : try await transcribe(recording.folder.appending(path: Self.othersTrack), .others)
        let transcript = MeetingLine.merged(mine, others)
        let note = MeetingNote(title: recording.title, start: recording.start, duration: duration,
                               app: recording.app?.name, summary: await summary(of: transcript), transcript: transcript)
        let written: NoteWriter.WrittenNote
        do {
            written = try await secondBrain.writeMeeting(note)
        } catch {
            Logger.meetings.error("Riunione note not written: \(error)")
            throw .noteNotWritten
        }
        if MeetingAudioRetention.saved(in: defaults) == .afterTranscription { store?.remove(recording.folder) }
        await removeExpiredAudio()
        return written.file
    }

    /// The summary of the first engine that writes one, of `transcript` without its secrets; `nil` when none does.
    func summary(of transcript: [MeetingLine]) async -> MeetingSummary? {
        guard !transcript.isEmpty else { return nil }
        let filter = SecretFilter()
        let text = filter.redacting(transcript.map(\.markdown).joined(separator: "\n"))
        for engine in engines {
            do {
                let answer = try await Self.summaryText(of: text, by: engine)
                let summary = MeetingSummary(markdown: answer).redacted(by: filter)
                if !summary.isEmpty { return summary }
            } catch {
                Logger.meetings.error("Riunione summary not written by an engine: \(String(describing: error), privacy: .public)")
            }
        }
        return nil
    }

    /// The summary `engine` writes of `text`, read in pieces of ``pieceLimit`` characters when longer: each piece
    /// summarized, then the summaries of the pieces summarized together, until they fit.
    ///
    /// - Throws: When the engine does not answer about a piece.
    static func summaryText(of text: String, by engine: any SummaryEngine) async throws -> String {
        var text = text
        var instructions = MeetingSummary.instructions
        while text.count > pieceLimit {
            var summaries: [String] = []
            for piece in MeetingSummary.pieces(of: text, limit: pieceLimit) {
                let answer = try await engine.shortText(for: piece, following: instructions, session: UUID())
                let summary = MeetingSummary(markdown: answer)
                if !summary.isEmpty { summaries.append(summary.markdown) }
            }
            let joined = summaries.joined(separator: "\n\n")
            guard !joined.isEmpty else { throw SummaryEngineError.emptyAnswer }
            // Summaries no shorter than their pieces would never fit: the engine reads what it can of them.
            guard joined.count < text.count else { break }
            text = joined
            instructions = MeetingSummary.joiningInstructions
        }
        return try await engine.shortText(for: text, following: instructions, session: UUID())
    }

    /// The most characters the summary engine reads at once: below the on-device model's limit, to leave room to
    /// the instructions.
    static let pieceLimit = 5_000

    private func fail(_ failure: MeetingFailure) {
        phase = .failed(failure)
        Logger.meetings.error("Riunione failed: \(String(describing: failure), privacy: .public)")
        announce(String(localized: failure.explanation))
        showWindow()
    }

    /// Says `text` to VoiceOver, whatever window is in front.
    private func announce(_ text: String) {
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    /// What turns the track at a URL, said by a speaker, into its sentences.
    typealias Transcription = (URL, MeetingLine.Speaker) async throws(MeetingFailure) -> [MeetingLine]

    @concurrent
    private static func removeExpired(in store: MeetingAudioStore) async {
        store.removeExpired()
    }

    /// The file of the microphone's track.
    private static let myTrack = "io.m4a"
    /// The file of the app's track.
    private static let othersTrack = "altri.m4a"
}
