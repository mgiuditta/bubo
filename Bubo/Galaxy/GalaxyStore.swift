import AppKit
import CoreServices
import os

/// The Galassia windows, one per Progetto: opening a Progetto already shown brings its window forward (spec 11).
final class GalaxyStore {
    /// The Progetti offered in each window's selector, most recent first.
    let projects: () -> [URL]
    /// Every Sessione, oldest first: their comets.
    let sessions: () -> [Session]
    private let viewer: () -> CodeViewerStore?
    /// The Sessioni's store: their changes and their revisione; `nil` without one.
    let sessionStore: () -> SessionStore?
    private var windows: [URL: GalaxyWindow] = [:]
    /// What the agents read and wrote since launch, for the windows open now and those opened later.
    private(set) var activity = GalaxyActivity()

    /// Creates the store, offering `projects`, showing the comets of `sessions`, opening files in the visore
    /// `viewer` gives and reading diffs from the store `sessionStore` gives.
    init(projects: @escaping () -> [URL], sessions: @escaping () -> [Session] = { [] },
         viewer: @escaping () -> CodeViewerStore?, sessionStore: @escaping () -> SessionStore? = { nil }) {
        self.projects = projects
        self.sessions = sessions
        self.viewer = viewer
        self.sessionStore = sessionStore
    }

    /// Records a file the agent of the Sessione `id` read or wrote, and lights it in the open windows at once.
    func record(_ progress: AgentProgress, by id: UUID) {
        guard let session = sessions().first(where: { $0.id == id }) else { return }
        let roots = GalaxySession.roots(of: session)
        switch progress {
        case let .read(files):
            activity.recordReads(files.compactMap { GalaxyActivity.relativePath(of: $0, in: roots) }, by: id)
        case let .edit(file, _):
            guard let path = GalaxyActivity.relativePath(of: file, in: roots) else { return }
            activity.recordWrite(path, by: id)
        default:
            return
        }
        for window in windows.values { window.model.update(activity: activity) }
    }

    /// Shows the Galassia of `project`, in its window if it has one, else in a new one.
    func show(_ project: URL) {
        let project = project.standardizedFileURL
        if let window = windows[project] {
            window.show()
            return
        }
        let model = GalaxyModel(project: project)
        model.update(activity: activity)
        let window = GalaxyWindow(model: model, store: self) { [weak self] in
            self?.windows[project] = nil
        }
        windows[project] = window
        window.show()
    }

    /// Asks for a folder and shows its Galassia.
    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = String(localized: "Mostra la Galassia")
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        show(folder)
    }

    /// Opens `path`, relative to `project`, in the visore.
    func open(_ path: String, in project: URL) {
        viewer()?.show(SourceLocation(file: project.appending(path: path)), in: project)
    }

    /// Reads into `model` the changes of `sessions` that have a revisione, then again after every write in their
    /// copies, until the task is cancelled: the same diff as their revisione.
    func followChanges(of sessions: [GalaxySession], into model: GalaxyModel) async {
        guard let store = sessionStore() else { return }
        await withDiscardingTaskGroup { group in
            for session in sessions where session.isReviewable {
                guard let folder = session.folder else { continue }
                group.addTask { await self.followChanges(of: session.id, in: folder, store: store, into: model) }
            }
        }
    }

    private func followChanges(of id: UUID, in folder: URL, store: SessionStore, into model: GalaxyModel) async {
        await readChanges(of: id, store: store, into: model)
        // A second of latency: an agent writing many files runs git once for them.
        let events = FileEvents.batches(under: folder.path, since: FSEventStreamEventId(kFSEventStreamEventIdSinceNow))
        for await batch in events {
            // git's own bookkeeping does not change the diff.
            guard batch.needsRescan || batch.paths.contains(where: { !$0.contains("/.git/") }) else { continue }
            await readChanges(of: id, store: store, into: model)
        }
    }

    private func readChanges(of id: UUID, store: SessionStore, into model: GalaxyModel) async {
        do {
            model.update(changes: try await store.changes(of: id), of: id)
        } catch is CancellationError {
        } catch {
            Logger.galaxy.error("Diff not read: \(String(describing: error), privacy: .private)")
            model.update(changes: nil, of: id)
        }
    }
}
