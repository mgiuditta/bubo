import Foundation

/// A durable unit of work on a Progetto, in its own copy of the Progetto when it is a git repo.
nonisolated struct Session: Codable, Identifiable, Equatable, Sendable {
    /// What a Sessione is doing now, in the order of the Colonna's groups.
    enum Activity: String, Codable, CaseIterable, Sendable {
        case attende, errore, lavora, ferma

        /// The Attività's name in the HUD; keyed, since "Ferma" is also a button.
        var title: LocalizedStringResource {
            switch self {
            case .attende: LocalizedStringResource("attivita.attendeTe", defaultValue: "Attende te")
            case .lavora: LocalizedStringResource("attivita.lavora", defaultValue: "Lavora")
            case .ferma: LocalizedStringResource("attivita.ferma", defaultValue: "Ferma")
            case .errore: LocalizedStringResource("attivita.errore", defaultValue: "Errore")
            }
        }
    }

    /// Where a Sessione is in its life.
    ///
    /// Fusa lasts as long as the merge can be undone; then the Sessione is Archiviata.
    // ponytail: In revisione comes when the revisione has a Fase of its own.
    enum Phase: String, Codable, Sendable {
        case aperta, fusa, archiviata

        /// The Fase's name in the HUD.
        var title: LocalizedStringResource {
            switch self {
            case .aperta: LocalizedStringResource("fase.aperta", defaultValue: "Aperta")
            case .fusa: LocalizedStringResource("fase.fusa", defaultValue: "Fusa")
            case .archiviata: LocalizedStringResource("fase.archiviata", defaultValue: "Archiviata")
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
    /// When the Sessione entered its Attività; `nil` in Sessioni saved before it was kept.
    var activitySince: Date?
    /// What the Sessione did or said last, in one line.
    var summary: String?
    /// Why the Sessione is in Errore, as git or `claude` wrote it.
    var failure: String?
    /// The Sessione's own ports, for its dev servers; `nil` when none was free.
    var ports: Range<Int>?
    /// Why the Progetto's setup script did not complete; the Sessione works anyway.
    var setupFailure: String?
    var phase = Phase.aperta
    /// The prompt the Sessione started with; `nil` in Sessioni saved before it was kept.
    var prompt: String?
    /// Whether Bubo quit while the Sessione was in Lavora: it waits for Riprendi.
    var isInterrupted = false
    /// Whether the Sessione works on the Progetto's checkout instead of its own copy: at most one per Progetto.
    var isOnCheckout = false
    /// The Cronologia CLI conversation the Sessione continues as a fork: `claude` resumes it, never in place.
    var forkedFrom: String?
    /// The writes the agent asked for, with why, the latest last: the perché of the blocchi in the revisione.
    var edits: [EditNote] = []
    /// What the user decided in the revisione, by blocco id.
    var decisions: [String: HunkDecision] = [:]

    /// Whether `claude` is still on the Sessione's turn: in Lavora, or in Attende te.
    var isRunning: Bool { activity == .lavora || activity == .attende }

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

nonisolated extension Session {
    /// Decodes a Sessione, also one saved before its Fase, its prompt, its checkout, its fork, its summary and its
    /// revisione were kept.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        project = try container.decode(URL.self, forKey: .project)
        workspace = try container.decodeIfPresent(Workspace.self, forKey: .workspace)
        activity = try container.decode(Activity.self, forKey: .activity)
        activitySince = try container.decodeIfPresent(Date.self, forKey: .activitySince)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        failure = try container.decodeIfPresent(String.self, forKey: .failure)
        ports = try container.decodeIfPresent(Range<Int>.self, forKey: .ports)
        setupFailure = try container.decodeIfPresent(String.self, forKey: .setupFailure)
        phase = try container.decodeIfPresent(Phase.self, forKey: .phase) ?? .aperta
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt)
        isInterrupted = try container.decodeIfPresent(Bool.self, forKey: .isInterrupted) ?? false
        isOnCheckout = try container.decodeIfPresent(Bool.self, forKey: .isOnCheckout) ?? false
        forkedFrom = try container.decodeIfPresent(String.self, forKey: .forkedFrom)
        edits = try container.decodeIfPresent([EditNote].self, forKey: .edits) ?? []
        decisions = try container.decodeIfPresent([String: HunkDecision].self, forKey: .decisions) ?? [:]
    }
}
