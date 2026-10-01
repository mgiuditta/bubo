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
    /// When Fondi merged the Sessione; `nil` until then, and once the merge is undone.
    var mergedAt: Date?
    /// The prompt the Sessione started with; `nil` in Sessioni saved before it was kept.
    var prompt: String?
    /// Whether Bubo quit while the Sessione was in Lavora: it waits for Riprendi.
    var isInterrupted = false
    /// Whether the Sessione works on the Progetto's checkout instead of its own copy: at most one per Progetto.
    var isOnCheckout = false
    /// The Cronologia CLI conversation the Sessione continues as a fork: `claude` resumes it, never in place.
    var forkedFrom: String?
    /// The ids of the agent's conversations, one per turn, oldest first: Bubo keeps a copy of each (ADR 0006).
    var conversations: [String] = []
    /// The writes the agent asked for, with why, the latest last: the perché of the blocchi in the revisione.
    var edits: [EditNote] = []
    /// What the user decided in the revisione, by blocco id.
    var decisions: [String: HunkDecision] = [:]
    /// The conflicts the agent is resolving in the worktree, with how to put it back; `nil` otherwise.
    var resolution: ConflictResolution?
    /// The issue the Sessione was started from with ⌘I; `nil` for the others.
    var issue: IssueLink?
    /// The prompt of the turn that did not start because its Sandbox could not, for Riprova; `nil` otherwise.
    var unstartedPrompt: String?
    /// Whether the user turned on the Modalità autonoma; it counts only where `allowsAutonomy`, from the next turn.
    var isAutonomous = false
    /// The latest lines Ricordato and Richiamato, the latest last, at most ``memoryLineLimit``.
    var memoryLines: [MemoryLine] = []

    /// The lines Ricordato and Richiamato a Sessione keeps.
    static let memoryLineLimit = 3

    /// Whether `claude` is still on the Sessione's turn: in Lavora, or in Attende te.
    var isRunning: Bool { activity == .lavora || activity == .attende }

    /// Whether the Modalità autonoma is possible: only in the Sessione's own worktree, never on the checkout nor
    /// outside git.
    var allowsAutonomy: Bool { !isOnCheckout && workspace?.branch != nil }

    /// How `claude` approves the calls of the Sessione's next turn.
    var permissionMode: PermissionMode { isAutonomous && allowsAutonomy ? .autonomous : .manual }

    /// Where the Sessione's terminal starts: its worktree, or the Progetto's folder outside git. `nil` on the
    /// checkout, once the Sessione is no longer Aperta, and while its copy is being prepared.
    var terminalFolder: URL? {
        guard phase == .aperta, !isOnCheckout else { return nil }
        return workspace?.folder
    }

    /// The branch the Sessione's copy is prepared on when it has none yet: from its issue, else from its title.
    var branchToPrepare: String {
        if let issue, issue.source == .github, let number = Int(issue.id) {
            return IssueLink.branch(forIssue: number, titled: title)
        }
        // From Linear the branch keeps the identifier, which links the PR to the issue.
        if let issue, issue.source == .linear { return Self.proposedBranch(for: "\(issue.id) \(title)") }
        return Self.proposedBranch(for: title)
    }

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
    /// Decodes a Sessione, also one saved before its Fase, its merge, its prompt, its checkout, its fork, its summary, its
    /// revisione, its conversations, its issue, its unstarted prompt, its Modalità autonoma and its lines Ricordato and
    /// Richiamato were kept.
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
        mergedAt = try container.decodeIfPresent(Date.self, forKey: .mergedAt)
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt)
        isInterrupted = try container.decodeIfPresent(Bool.self, forKey: .isInterrupted) ?? false
        isOnCheckout = try container.decodeIfPresent(Bool.self, forKey: .isOnCheckout) ?? false
        forkedFrom = try container.decodeIfPresent(String.self, forKey: .forkedFrom)
        conversations = try container.decodeIfPresent([String].self, forKey: .conversations) ?? []
        edits = try container.decodeIfPresent([EditNote].self, forKey: .edits) ?? []
        decisions = try container.decodeIfPresent([String: HunkDecision].self, forKey: .decisions) ?? [:]
        resolution = try container.decodeIfPresent(ConflictResolution.self, forKey: .resolution)
        issue = try container.decodeIfPresent(IssueLink.self, forKey: .issue)
        unstartedPrompt = try container.decodeIfPresent(String.self, forKey: .unstartedPrompt)
        isAutonomous = try container.decodeIfPresent(Bool.self, forKey: .isAutonomous) ?? false
        memoryLines = try container.decodeIfPresent([MemoryLine].self, forKey: .memoryLines) ?? []
    }
}
