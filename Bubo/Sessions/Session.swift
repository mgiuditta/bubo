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
    /// The Sessione's own ports, for its dev servers; `nil` when none was free.
    var ports: Range<Int>?
    /// Why the Progetto's setup script did not complete; the Sessione works anyway.
    var setupFailure: String?

    /// The variables that hand the Sessione's ports to what runs in it: `PORT` and `BUBO_PORT` the first,
    /// `BUBO_PORTS` all of them as `first-last`.
    var portEnvironment: [String: String] {
        guard let ports, let last = ports.last else { return [:] }
        let first = String(ports.lowerBound)
        return ["PORT": first, "BUBO_PORT": first, "BUBO_PORTS": "\(first)-\(last)"]
    }

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
