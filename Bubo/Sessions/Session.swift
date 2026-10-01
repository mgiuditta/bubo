import Foundation

/// A durable unit of work on a Progetto, in its own copy of the Progetto when it is a git repo.
nonisolated struct Session: Codable, Identifiable, Equatable, Sendable {
    /// What a Sessione is doing now.
    enum Activity: String, Codable, Sendable {
        case lavora, ferma, errore

        /// The Attività's name in the HUD; keyed, since "Ferma" is also a button.
        var title: LocalizedStringResource {
            switch self {
            case .lavora: LocalizedStringResource("attivita.lavora", defaultValue: "Lavora")
            case .ferma: LocalizedStringResource("attivita.ferma", defaultValue: "Ferma")
            case .errore: LocalizedStringResource("attivita.errore", defaultValue: "Errore")
            }
        }
    }

    let id: UUID
    /// The title, proposed from the first prompt.
    var title: String
    /// The Progetto's folder.
    var project: URL
    /// Where the Sessione works; `nil` while its copy is being prepared.
    var workspace: Workspace?
    var activity = Activity.lavora
    /// Why the Sessione is in Errore, as git or `claude` wrote it.
    var failure: String?

    /// A title for a Sessione that starts with `prompt`: its first six words.
    static func proposedTitle(for prompt: String) -> String {
        prompt.split(whereSeparator: \.isWhitespace).prefix(6).joined(separator: " ")
    }

    /// A branch for a Sessione titled `title`: `bubo/` and the title in lowercase ASCII, words joined by `-`.
    static func proposedBranch(for title: String) -> String {
        let words = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .lowercased()
            .split { !($0.isASCII && ($0.isLetter || $0.isNumber)) }
        var slug = ""
        for word in words where slug.count + word.count < 40 {
            slug += slug.isEmpty ? String(word) : "-\(word)"
        }
        return "bubo/\(slug.isEmpty ? "sessione" : slug)"
    }
}
