import Foundation
import Observation
import os

/// The Secondo cervello: the folder the user chose, followed by the Indice while Bubo runs.
///
/// Its notes reach the model only through the `cerca` tool, when the model calls it: nothing is added to a
/// conversation on its own.
@Observable
final class SecondBrain {
    /// Creates the Secondo cervello saved in `defaults`, followed by `index` once started.
    init(index: SearchIndex?, defaults: UserDefaults = .standard) {
        self.index = index
        self.defaults = defaults
        location = SecondBrainLocation.saved(in: defaults)
    }

    /// The chosen folder; `nil` while the user has not chosen one.
    private(set) var location: SecondBrainLocation?

    @ObservationIgnored private let index: SearchIndex?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var following: Task<Void, Never>?

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

    /// Saves `text` as a new note titled `title` in `Bubo/Note/`, off the main actor.
    ///
    /// - Returns: The note; `nil` when no folder is chosen, so nothing is written.
    /// - Throws: `NoteWriter.Failure` or a file system error when the note could not be written.
    func remember(_ text: String, titled title: String) async throws -> NoteWriter.WrittenNote? {
        guard let location else { return nil }
        let note = try await Self.write(text, titled: title, with: NoteWriter(root: location.url))
        Logger.index.notice("Note saved in the Secondo cervello")
        return note
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

    @concurrent
    private static func writeSessionSummary(_ body: String, properties: SummaryProperties, replacing previous: SummaryNote?,
                                            with writer: NoteWriter) async throws -> SummaryNote? {
        try writer.writeSessionSummary(body, properties: properties, replacing: previous)
    }

    @concurrent
    private static func write(_ text: String, titled title: String,
                              with writer: NoteWriter) async throws -> NoteWriter.WrittenNote {
        try writer.remember(text, titled: title)
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
        following = Task(priority: .utility) { [index] in
            await index?.keepSecondBrainFresh(at: folder, excluding: excludedFolders)
        }
    }
}
