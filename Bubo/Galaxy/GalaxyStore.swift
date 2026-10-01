import AppKit

/// The Galassia windows, one per Progetto: opening a Progetto already shown brings its window forward (spec 11).
final class GalaxyStore {
    /// The Progetti offered in each window's selector, most recent first.
    let projects: () -> [URL]
    /// Every Sessione, oldest first: their comets.
    let sessions: () -> [Session]
    private let viewer: () -> CodeViewerStore?
    private var windows: [URL: GalaxyWindow] = [:]
    /// What the agents read and wrote since launch, for the windows open now and those opened later.
    private(set) var activity = GalaxyActivity()

    /// Creates the store, offering `projects`, showing the comets of `sessions` and opening files in the visore
    /// `viewer` gives.
    init(projects: @escaping () -> [URL], sessions: @escaping () -> [Session] = { [] },
         viewer: @escaping () -> CodeViewerStore?) {
        self.projects = projects
        self.sessions = sessions
        self.viewer = viewer
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
}
