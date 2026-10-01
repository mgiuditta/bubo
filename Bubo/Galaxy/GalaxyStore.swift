import AppKit

/// The Galassia windows, one per Progetto: opening a Progetto already shown brings its window forward (spec 11).
final class GalaxyStore {
    /// The Progetti offered in each window's selector, most recent first.
    let projects: () -> [URL]
    private let viewer: () -> CodeViewerStore?
    private var windows: [URL: GalaxyWindow] = [:]

    /// Creates the store, offering `projects` and opening files in the visore `viewer` gives.
    init(projects: @escaping () -> [URL], viewer: @escaping () -> CodeViewerStore?) {
        self.projects = projects
        self.viewer = viewer
    }

    /// Shows the Galassia of `project`, in its window if it has one, else in a new one.
    func show(_ project: URL) {
        let project = project.standardizedFileURL
        if let window = windows[project] {
            window.show()
            return
        }
        let window = GalaxyWindow(model: GalaxyModel(project: project), store: self) { [weak self] in
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
