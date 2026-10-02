import AppIntents
import Foundation

/// A Progetto as the parameter of "Nuova Sessione": its folder, named after it.
///
/// The known Progetti are those with Sessioni; a saved shortcut keeps the folder's path even after it is gone, so
/// the intent can say so.
struct ProjectEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Progetto"
    static let defaultQuery = ProjectQuery()

    /// The folder's path.
    let id: String

    /// Creates the entity of the Progetto in `folder`.
    init(folder: URL) {
        id = folder.path(percentEncoded: false)
    }

    /// Creates the entity of the Progetto whose folder's path is `id`.
    init(id: String) {
        self.id = id
    }

    /// The Progetto's folder.
    var folder: URL { URL(filePath: id, directoryHint: .isDirectory) }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(folder.lastPathComponent)", subtitle: "\(id)")
    }
}

/// The Progetti "Nuova Sessione" offers: those with Sessioni, most recent first.
struct ProjectQuery: EntityQuery {
    func entities(for identifiers: [ProjectEntity.ID]) async throws -> [ProjectEntity] {
        identifiers.map(ProjectEntity.init(id:))
    }

    func suggestedEntities() async throws -> [ProjectEntity] {
        await NewSessionIntent.knownProjects().map(ProjectEntity.init(folder:))
    }
}
