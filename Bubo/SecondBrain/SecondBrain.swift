import Foundation
import Observation
import os

/// The Secondo cervello: the folder the user chose, followed by the Indice while Bubo runs.
///
/// Its notes reach the model through the `cerca` tool, when the model calls it; only `Bubo/Profilo.md` and
/// `Bubo/Regole.md` come into every turn, as ``basics()``.
@Observable
final class SecondBrain {
    /// Creates the Secondo cervello saved in `defaults`, followed by `index` once started, keeping its writes in
    /// `journal`.
    init(index: SearchIndex?, defaults: UserDefaults = .standard, journal: BrainJournal = .standard) {
        self.index = index
        self.defaults = defaults
        self.journal = journal
        location = SecondBrainLocation.saved(in: defaults)
        savesOnItsOwn = defaults.object(forKey: Self.savesOnItsOwnKey) as? Bool ?? true
        recentChanges = journal.changes()
    }

    /// Where ``savesOnItsOwn`` is kept.
    static let savesOnItsOwnKey = "secondBrain.savesOnItsOwn"

    /// Salva da solo: whether the agent saves durable facts about the user on its own, following `Regole.md`;
    /// otherwise it saves only when asked.
    var savesOnItsOwn: Bool {
        didSet { defaults.set(savesOnItsOwn, forKey: Self.savesOnItsOwnKey) }
    }

    /// Bubo's latest writes in the Secondo cervello, newest first, for Annulla.
    private(set) var recentChanges: [BrainChange]

    /// The chosen folder; `nil` while the user has not chosen one.
    private(set) var location: SecondBrainLocation?

    @ObservationIgnored private let index: SearchIndex?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let journal: BrainJournal
    @ObservationIgnored private var following: Task<Void, Never>?
    @ObservationIgnored private var prioritizing: Task<Void, Never>?

    /// Starts following the chosen folder, at its new path when it was moved while Bubo was closed.
    func start() {
        if let location {
            let resolved = location.resolved()
            if resolved != location { remember(resolved) }
        }
        follow()
    }

    /// Makes `folder` the Secondo cervello, replacing the previous one in the Indice.
    func choose(_ folder: URL) {
        remember(SecondBrainLocation(folder: folder))
        follow()
    }

    /// Leaves `folder`, inside the Secondo cervello, out of the Indice; its notes stay where they are.
    ///
    /// - Throws: ``SecondBrainExclusionError/outsideSecondBrain`` for a folder outside it, or the Secondo cervello itself.
    func exclude(_ folder: URL) throws(SecondBrainExclusionError) {
        guard var location, let relativePath = location.relativePath(of: folder) else {
            throw .outsideSecondBrain
        }
        guard !location.excludedFolders.contains(relativePath) else { return }
        location.excludedFolders = (location.excludedFolders + [relativePath]).sorted()
        remember(location)
        follow()
    }

    /// Brings back into the Indice the folder at `relativePath`, relative to the Secondo cervello.
    func include(_ relativePath: String) {
        guard var location, location.excludedFolders.contains(relativePath) else { return }
        location.excludedFolders.removeAll { $0 == relativePath }
        remember(location)
        follow()
    }

    /// Leaves out of the Indice exactly the folders at `relativePaths`, relative to the Secondo cervello, as the
    /// guided setup answers; the others come back.
    func excludeOnly(_ relativePaths: Set<String>) {
        guard var location, Set(location.excludedFolders) != relativePaths else { return }
        location.excludedFolders = relativePaths.sorted()
        location.priorityFolders.removeAll { relativePaths.contains($0) }
        remember(location)
        follow()
    }

    /// Makes `cerca` put first the notes of `folder`, inside the Secondo cervello.
    ///
    /// - Throws: ``SecondBrainExclusionError/outsideSecondBrain`` for a folder outside it, or the Secondo cervello itself.
    func prioritize(_ folder: URL) throws(SecondBrainExclusionError) {
        guard let location, let relativePath = location.relativePath(of: folder) else { throw .outsideSecondBrain }
        prioritizeOnly(Set(location.priorityFolders + [relativePath]))
    }

    /// Makes `cerca` put first exactly the notes of the folders at `relativePaths`, relative to the Secondo cervello.
    func prioritizeOnly(_ relativePaths: Set<String>) {
        guard var location, Set(location.priorityFolders) != relativePaths else { return }
        location.priorityFolders = relativePaths.sorted()
        remember(location)
        sendProfile()
    }

    /// Makes `cerca` put first the notes naming one of `people` or `projects`, as the guided setup answers.
    func prioritize(people: [String], projects: [String]) {
        guard var location, location.people != people || location.projects != projects else { return }
        location.people = people
        location.projects = projects
        remember(location)
        sendProfile()
    }

    /// How full the Indice is; `nil` until first read.
    private(set) var fragmentLoad: FragmentLoad?

    /// Reads again how full the Indice is.
    func refreshFragmentLoad() async {
        do {
            fragmentLoad = try await index?.fragmentLoad()
        } catch {
            Logger.index.error("Could not count the fragments: \(error)")
        }
    }

    /// Stops using the Secondo cervello: the Indice forgets its notes; the folder is left as it is.
    func stopUsing() {
        remember(nil)
        follow()
    }

    /// Writes what `request` asks for the `ricorda` tool, off the main actor, keeping it in the diario.
    ///
    /// - Returns: What the tool answers the model, and the write when there was one.
    func remember(_ request: NoteRequest) async -> (reply: String, change: BrainChange?) {
        guard let location else {
            return ("Nota non salvata: l'utente non ha scelto il Secondo cervello. Digli di sceglierlo in "
                + "Impostazioni › Generale › Secondo cervello.", nil)
        }
        do {
            let change = try await Self.write(request, with: NoteWriter(root: location.url))
            do {
                recentChanges = try journal.record(change)
            } catch {
                Logger.index.error("Write not kept in the diario: \(error)")
            }
            Logger.index.notice("Note saved in the Secondo cervello")
            let path = location.relativePath(of: change.file) ?? change.file.lastPathComponent
            return ("Salvato nel Secondo cervello: \(path). L'utente vede «Salvato in \(change.link)» e può "
                + "annullare.", change)
        } catch NoteWriter.Failure.unreachable {
            return ("Nota non salvata: la cartella del Secondo cervello non è raggiungibile (disco scollegato o "
                + "cartella spostata).", nil)
        } catch NoteWriter.Failure.needsConfirmation {
            return ("Nota non riscritta: è una nota dell'utente, fuori da Bubo/. Chiedigli se puoi riscriverla e, solo "
                + "se dice di sì, richiama ricorda con confermato: true. Per aggiungere in coda usa modo \"aggiungi\".",
                nil)
        } catch NoteWriter.Failure.notFound {
            return ("Nota non salvata: la nota indicata non esiste. Cercala con cerca, o crea una nota nuova.", nil)
        } catch NoteWriter.Failure.outsideSecondBrain, NoteWriter.Failure.outsideBubo {
            return ("Nota non salvata: indica una nota .md dentro il Secondo cervello, con il percorso relativo alla "
                + "sua cartella.", nil)
        } catch {
            Logger.index.error("Note not saved: \(error)")
            return ("Nota non salvata: Bubo non è riuscito a scriverla.", nil)
        }
    }

    /// Annulla: puts the note of `change` back as it was before the write, and marks it undone in the diario.
    ///
    /// - Throws: ``BrainChange/UndoFailure/changedOnDisk`` when the note changed after the write, or a file error.
    func undo(_ change: BrainChange) throws {
        guard recentChanges.first(where: { $0.id == change.id })?.isUndone != true else { return }
        try change.undo()
        recentChanges = (try? journal.markUndone(change.id)) ?? recentChanges
    }

    /// The text every turn of a Domanda or a Sessione gets in its system prompt: `Bubo/Profilo.md` and
    /// `Bubo/Regole.md`, as ``SecondBrainBasics`` builds it; `nil` without a folder or when neither note is there.
    func basics() -> String? {
        location.flatMap { SecondBrainBasics.prompt(in: $0.url, savesOnItsOwn: savesOnItsOwn) }
    }

    /// Writes the Riassunto di Sessione `body` in `Bubo/Sessioni/`, off the main actor, as
    /// ``NoteWriter/writeSessionSummary(_:properties:replacing:)`` does.
    ///
    /// - Returns: The note; `nil` when `previous` was deleted, so nothing is written.
    /// - Throws: `NoteWriter.Failure.unreachable` also when no folder is chosen; a file system error when the note
    ///   could not be written.
    func writeSessionSummary(_ body: String, properties: SummaryProperties,
                             replacing previous: SummaryNote?) async throws -> SummaryNote? {
        guard let location else { throw NoteWriter.Failure.unreachable }
        return try await Self.writeSessionSummary(body, properties: properties, replacing: previous,
                                                  with: NoteWriter(root: location.url))
    }

    /// Writes the Riunione `note` in `Bubo/Riunioni/`, off the main actor; the Indice finds it as any other note.
    ///
    /// - Throws: `NoteWriter.Failure.unreachable` also when no folder is chosen; a file system error when the note
    ///   could not be written.
    func writeMeeting(_ note: MeetingNote) async throws -> NoteWriter.WrittenNote {
        guard let location else { throw NoteWriter.Failure.unreachable }
        let written = try await Self.writeMeeting(note, with: NoteWriter(root: location.url))
        Logger.index.notice("Riunione saved in the Secondo cervello")
        return written
    }

    @concurrent
    private static func writeMeeting(_ note: MeetingNote, with writer: NoteWriter) async throws -> NoteWriter.WrittenNote {
        try writer.writeMeeting(note)
    }

    @concurrent
    private static func writeSessionSummary(_ body: String, properties: SummaryProperties, replacing previous: SummaryNote?,
                                            with writer: NoteWriter) async throws -> SummaryNote? {
        try writer.writeSessionSummary(body, properties: properties, replacing: previous)
    }

    @concurrent
    private static func write(_ request: NoteRequest, with writer: NoteWriter) async throws -> BrainChange {
        switch request.mode {
        case .new:
            let note = try writer.remember(request.text, titled: request.title ?? "Nota")
            return BrainChange(file: note.file, previous: nil, hash: note.hash)
        case .append:
            return try writer.append(request.text, to: request.note ?? "")
        case .replace:
            return try writer.rewrite(request.note ?? "", with: request.text, isConfirmed: request.isConfirmed)
        }
    }

    private func remember(_ location: SecondBrainLocation?) {
        self.location = location
        SecondBrainLocation.save(location, in: defaults)
        Logger.index.notice("Secondo cervello \(location == nil ? "removed" : "chosen", privacy: .public)")
    }

    private func follow() {
        following?.cancel()
        let folder = location?.url
        let excludedFolders = Set(location?.excludedFolders ?? [])
        sendProfile()
        following = Task(priority: .utility) { [index] in
            await index?.keepSecondBrainFresh(at: folder, excluding: excludedFolders)
        }
    }

    /// Hands the Indice the folders and the names `cerca` puts first, without reading the notes again.
    private func sendProfile() {
        let priorityFolders = Set(location?.priorityFolders ?? [])
        let names = (location?.people ?? []) + (location?.projects ?? [])
        // Chained, so the Indice ends with the last choice even when two are sent in a row.
        prioritizing = Task { [index, previous = prioritizing] in
            await previous?.value
            await index?.prioritize(priorityFolders, names: names)
        }
    }
}
