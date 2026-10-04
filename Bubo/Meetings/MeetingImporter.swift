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
    @ObservationIgnored private let videoDownloader: VideoDownloader

    /// Creates the importer.
    ///
    /// - Parameters:
    ///   - secondBrain: Where the notes go.
    ///   - summarize: Writes the summary of a trascrizione; `nil` when no model can.
    ///   - showWindow: Opens the window of the Riunioni, where the import shows.
    ///   - videoDownloader: Downloads the audio of a web video.
    init(secondBrain: SecondBrain, summarize: @escaping ([MeetingLine]) async -> MeetingSummary?,
         showWindow: @escaping () -> Void = {}, videoDownloader: VideoDownloader = VideoDownloader()) {
        self.secondBrain = secondBrain
        self.summarize = summarize
        self.showWindow = showWindow
        self.videoDownloader = videoDownloader
    }

    /// Asks for the link of a web video, prefilled from the clipboard when it holds one, then imports it.
    func chooseVideoLink() {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        field.placeholderString = "https://"
        field.setAccessibilityLabel(String(localized: "Link del video"))
        if let copied = NSPasteboard.general.string(forType: .string),
           let link = URL(string: copied.trimmingCharacters(in: .whitespacesAndNewlines)), Self.isWebLink(link) {
            field.stringValue = link.absoluteString
        }
        let alert = NSAlert()
        alert.messageText = String(localized: "Trascrivi un video da un link")
        alert.informativeText = String(localized: "Bubo scarica solo l'audio, lo trascrive e salva la Riunione nel Secondo cervello.")
        alert.accessoryView = field
        alert.addButton(withTitle: String(localized: "Trascrivi"))
        alert.addButton(withTitle: String(localized: "Annulla"))
        alert.window.initialFirstResponder = field
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn,
              let link = URL(string: field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)),
              Self.isWebLink(link)
        else { return }
        start(importingVideoAt: link)
    }

    /// Imports the web video at `link` as a Riunione in the background; ignored while another import runs.
    ///
    /// - Parameter onNoVideo: Called instead of showing a failure when the link has no video, or the user does not
    ///   let Bubo download `yt-dlp`: a dropped link then becomes an Allegato.
    func start(importingVideoAt link: URL, onNoVideo: (() -> Void)? = nil) {
        guard task == nil else { return }
        task = Task {
            await importVideo(at: link, onNoVideo: onNoVideo)
            task = nil
        }
    }

    /// Whether `link` is an `http` or `https` address.
    static func isWebLink(_ link: URL) -> Bool {
        ["http", "https"].contains(link.scheme?.lowercased()) && link.host() != nil
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

    /// Downloads the audio of `link`, transcribes it and saves the Riunione, titled as the video; sets ``outcome``.
    func importVideo(at link: URL, onNoVideo: (() -> Void)?) async {
        outcome = nil
        defer { progress = nil }
        var outcome = Outcome()
        let fingerprint = VideoDownloader.fingerprint(of: link)
        do throws(MeetingFailure) {
            guard let root = secondBrain.location?.url else { throw .noSecondBrain }
            let known = await Self.fingerprints(inNotesAt: root.appending(path: NoteWriter.meetingFolder))
            if known.contains(fingerprint) {
                showWindow()
                outcome.duplicates = 1
            } else {
                let executable: URL
                if let installed = await videoDownloader.installedExecutable() {
                    executable = installed
                } else {
                    guard Self.mayInstallDownloader() else {
                        onNoVideo?()
                        return
                    }
                    executable = try await videoDownloader.install()
                }
                showWindow()
                progress = Progress(done: 0, total: 1, fileName: link.host() ?? link.absoluteString)
                await videoDownloader.updateIfDue(executable)
                let video = try await videoDownloader.download(link, with: executable)
                defer { try? FileManager.default.removeItem(at: video.folder) }
                var note = try await Self.note(of: video.audio)
                note.title = video.title
                note.start = .now
                note.source = MeetingNote.Source(fileName: video.title, fingerprint: fingerprint, link: link)
                note.summary = await summarize(note.transcript)
                if !Task.isCancelled { outcome.saved.append(try await write(note)) }
            }
        } catch .noVideo where onNoVideo != nil && !Task.isCancelled {
            onNoVideo?()
            return
        } catch {
            Logger.meetings.error("Video Riunione not imported: \(String(describing: error), privacy: .public)")
            if !Task.isCancelled {
                showWindow()
                outcome.failures.append(Failure(fileName: link.absoluteString, reason: error))
            }
        }
        outcome.isCancelled = Task.isCancelled
        self.outcome = outcome
        announce(outcome)
    }

    /// Asks whether Bubo may download `yt-dlp`, which it needs for web videos.
    private static func mayInstallDownloader() -> Bool {
        let alert = NSAlert()
        alert.messageText = String(localized: "Scarico yt-dlp per trascrivere il video?")
        alert.informativeText = String(localized: "Bubo usa yt-dlp, un programma libero, per scaricare l'audio dei video dal web. Lo scarica da GitHub, ne controlla l'impronta e lo tiene nella sua cartella.")
        alert.addButton(withTitle: String(localized: "Scarica e trascrivi"))
        alert.addButton(withTitle: String(localized: "Annulla"))
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
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
