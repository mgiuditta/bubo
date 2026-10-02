import Foundation

/// The Sessione a Domanda's Allegati propose (spec 09, Cosa nasce); `nil` from ``init(for:projects:isRepository:)``
/// when they propose none.
///
/// A Progetto is known when it has Sessioni (`SessionStore.projects`): Bubo keeps no other register of Progetti.
nonisolated enum SessionProposal: Equatable, Sendable {
    /// Every file is inside this known Progetto: "Trasforma in Sessione su <Progetto>".
    case session(on: URL)
    /// The Allegato is a git repo that is not a Progetto yet: "Apri come Progetto e crea Sessione".
    case newProject(URL)

    /// The Progetto the Sessione would work on.
    var project: URL {
        switch self {
        case let .session(project), let .newProject(project): project
        }
    }

    /// Creates the proposal for `attachments`, or `nil` when they propose no Sessione: files from more Progetti, files
    /// outside every Progetto, or only text.
    ///
    /// Text with no file behind it does not count; a folder that is itself a known Progetto counts as inside it.
    ///
    /// - Parameters:
    ///   - projects: The known Progetti.
    ///   - isRepository: Whether a folder is the top of a git repo.
    init?(for attachments: [Allegato], projects: [URL], isRepository: (URL) -> Bool = SessionProposal.isRepository) {
        let paths = attachments.compactMap(\.path)
        guard !paths.isEmpty else { return nil }
        let owners = paths.map { path in Self.project(containing: path, among: projects) }
        if let first = owners.first, let project = first, owners.allSatisfy({ $0 == project }) {
            self = .session(on: project)
            return
        }
        guard owners.allSatisfy({ $0 == nil }), paths.count == 1, let folder = attachments.first(where: { $0.path != nil }),
              folder.kind == .folder, let path = folder.path, isRepository(path)
        else { return nil }
        self = .newProject(path)
    }

    /// The known Progetto among `projects` that holds `path`, the innermost when they nest; `nil` for none.
    private static func project(containing path: URL, among projects: [URL]) -> URL? {
        let components = path.standardizedFileURL.pathComponents
        return projects
            .filter { project in
                let root = project.standardizedFileURL.pathComponents
                return components.starts(with: root)
            }
            .max { $0.standardizedFileURL.pathComponents.count < $1.standardizedFileURL.pathComponents.count }
    }

    /// Whether `folder` is the top of a git repo: it holds `.git`, a folder in a checkout or a file in a worktree.
    static func isRepository(_ folder: URL) -> Bool {
        FileManager.default.fileExists(atPath: folder.appending(path: ".git").path(percentEncoded: false))
    }
}
