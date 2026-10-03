import AppKit
import Observation
import os
import UniformTypeIdentifiers

/// Imports recordings and trascrizioni as Riunioni, one file at a time and off the main actor: audio and video are
/// transcribed on the Mac, trascrizioni cleaned, then summarized and saved in `Bubo/Riunioni/` as a recorded Riunione.
///
/// A file already imported, known by the `impronta` of its note, is skipped.
@Observable
final class MeetingImporter {
    /// How far an import is.
    struct Progress: Equatable {
        /// The files done, imported or not.
        var done: Int
        var total: Int
        /// The name of the file being imported.
        var fileName: String
    }

    /// A file not imported, and why.
    struct Failure: Equatable, Identifiable {
        let id = UUID()
        /// The file's name; `nil` when the whole import failed.
        var fileName: String?
        var reason: MeetingFailure
    }

    /// How the last import ended.
    struct Outcome: Equatable {
        /// The notes written.
        var saved: [URL] = []
        /// The files skipped as already imported.
        var duplicates = 0
        var failures: [Failure] = []
        /// Whether the user stopped it before the last file.
        var isCancelled = false
    }

    /// Where the running import is; `nil` when none runs.
    private(set) var progress: Progress?
    /// How the last import ended; `nil` before the first, and while one runs.
    private(set) var outcome: Outcome?

    /// Whether an import is running.
    var isImporting: Bool { task != nil }

    private var task: Task<Void, Never>?
    @ObservationIgnored private let secondBrain: SecondBrain
    @ObservationIgnored private let summarize: ([MeetingLine]) async -> MeetingSummary?
    @ObservationIgnored private let showWindow: () -> Void

    /// Creates the importer.
    ///
    /// - Parameters:
    ///   - secondBrain: Where the notes go.
    ///   - summarize: Writes the summary of a trascrizione; `nil` when no model can.
    ///   - showWindow: Opens the window of the Riunioni, where the import shows.
    init(secondBrain: SecondBrain, summarize: @escaping ([MeetingLine]) async -> MeetingSummary?,
         showWindow: @escaping () -> Void = {}) {
        self.secondBrain = secondBrain
        self.summarize = summarize
        self.showWindow = showWindow
    }

    /// Asks for files or folders to import, then imports them.
    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.prompt = String(localized: "Importa")
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.audio, .movie, .plainText] + ["vtt", "srt"].compactMap { UTType(filenameExtension: $0) }
        NSApp.activate()
        guard panel.runModal() == .OK else { return }
        start(importing: panel.urls)
    }

    /// Imports the files and folders `urls` in the background, shown in the window of the Riunioni; ignored while
    /// another import runs.
    func start(importing urls: [URL]) {
        showWindow()
        guard task == nil else { return }
        task = Task {
            await importFiles(urls)
            task = nil
        }
    }

    /// Stops the import after the file being imported, which is not saved.
    func cancel() {
        task?.cancel()
    }

    /// Imports the files and folders `urls`, sets ``outcome`` and tells VoiceOver.
    func importFiles(_ urls: [URL]) async {
        outcome = nil
        defer { progress = nil }
        var outcome = Outcome()
        if let root = secondBrain.location?.url {
            let files = await Self.files(in: urls)
            var known = await Self.fingerprints(inNotesAt: root.appending(path: NoteWriter.meetingFolder))
            Logger.meetings.notice("Importing \(files.count, privacy: .public) Riunioni files")
            for (index, file) in files.enumerated() {
                guard !Task.isCancelled else { break }
                progress = Progress(done: index, total: files.count, fileName: file.lastPathComponent)
                do throws(MeetingFailure) {
                    let fingerprint = try await Self.fingerprint(of: file)
                    guard !known.contains(fingerprint) else {
                        outcome.duplicates += 1
                        continue
                    }
                    var note = try await Self.note(of: file)
                    note.source = MeetingNote.Source(fileName: file.lastPathComponent, fingerprint: fingerprint)
                    note.summary = await summarize(note.transcript)
                    guard !Task.isCancelled else { break }
                    outcome.saved.append(try await write(note))
                    known.insert(fingerprint)
                } catch {
                    guard !Task.isCancelled else { break }
                    Logger.meetings.error("Riunione not imported: \(String(describing: error), privacy: .public)")
                    outcome.failures.append(Failure(fileName: file.lastPathComponent, reason: error))
                }
            }
        } else {
            outcome.failures.append(Failure(fileName: nil, reason: .noSecondBrain))
        }
        outcome.isCancelled = Task.isCancelled
        self.outcome = outcome
        announce(outcome)
    }

    private func write(_ note: MeetingNote) async throws(MeetingFailure) -> URL {
        do {
            return try await secondBrain.writeMeeting(note).file
        } catch {
            Logger.meetings.error("Imported Riunione note not written: \(error)")
            throw .noteNotWritten
        }
    }

    /// Says how the import ended to VoiceOver, whatever window is in front.
    private func announce(_ outcome: Outcome) {
        let text = outcome.isCancelled ? String(localized: "Importazione annullata. Riunioni importate: \(outcome.saved.count)")
            : String(localized: "Importazione completata. Riunioni importate: \(outcome.saved.count)")
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    /// The Riunione of `file`, without summary nor source: its trascrizione, its date and, when known, how long it lasts.
    @concurrent
    private static func note(of file: URL) async throws(MeetingFailure) -> MeetingNote {
        var note = MeetingNote(title: file.deletingPathExtension().lastPathComponent, start: MeetingImportFile.date(of: file),
                               duration: nil, app: nil, transcript: [])
        switch MeetingImportFile.kind(of: file) {
        case .audio:
            note.duration = await MeetingImportFile.duration(of: file)
            note.transcript = try await MeetingTranscriber.transcribe(file, as: nil)
        case .video:
            note.duration = await MeetingImportFile.duration(of: file)
            let audio = try await MeetingImportFile.audio(ofVideo: file)
            defer { try? FileManager.default.removeItem(at: audio.deletingLastPathComponent()) }
            note.transcript = try await MeetingTranscriber.transcribe(audio, as: nil)
        case .subtitles:
            (note.transcript, note.duration) = MeetingImportFile.lines(ofSubtitles: try MeetingImportFile.text(of: file))
        case .text:
            note.transcript = MeetingImportFile.lines(ofText: try MeetingImportFile.text(of: file))
        case nil:
            throw .fileUnreadable
        }
        return note
    }

    @concurrent
    private static func fingerprint(of file: URL) async throws(MeetingFailure) -> String {
        do {
            return try MeetingImportFile.fingerprint(of: file)
        } catch {
            throw .fileUnreadable
        }
    }

    @concurrent
    private static func files(in urls: [URL]) async -> [URL] {
        MeetingImportFile.files(in: urls)
    }

    @concurrent
    private static func fingerprints(inNotesAt folder: URL) async -> Set<String> {
        MeetingImportFile.fingerprints(inNotesAt: folder)
    }
}
