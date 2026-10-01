import Foundation

/// The Richieste di permesso of the Sessioni, queued per Sessione oldest first, and the permissions given
/// "Per questa Sessione", kept only in memory: they end when Bubo quits or the Sessione is deleted.
nonisolated struct RequestCenter: Equatable {
    /// A Richiesta waiting for the user, with its risk.
    struct Pending: Identifiable, Equatable {
        let request: PermissionRequest
        let risk: Risk
        let since: Date

        var id: PermissionRequest.ID { request.id }

        /// Whether approving takes a 1-second press: level 4–5, or `claude` says one key must not approve it.
        var needsHold: Bool { risk.level.isDangerous || request.defaultsToNo }
        /// Whether "Per questa Sessione" is offered: never from levels 4–5, nor when `claude` says no lasting permission.
        var allowsSessionRule: Bool { !needsHold && !request.suppressesRule && SessionRule(request) != nil }
    }

    /// What happens to a Richiesta as it arrives.
    enum Verdict: Equatable {
        /// Refused at once: it removes a critical path of `claude`.
        case denied
        /// Allowed at once by a permission given for the Sessione.
        case allowed
        /// Waiting for the user.
        case queued
    }

    /// The Richieste waiting in each Sessione, oldest first.
    private(set) var queues: [UUID: [Pending]] = [:]
    private var sessionRules: [UUID: Set<SessionRule>] = [:]

    /// The Richiesta the keyboard answers: the oldest one across the Sessioni.
    var first: Pending? {
        queues.values.compactMap(\.first).min { $0.since < $1.since }
    }

    /// Takes `request` from `session`, whose calls carry `risk`.
    mutating func receive(_ request: PermissionRequest, in session: UUID, risk: Risk, at date: Date = .now) -> Verdict {
        if risk.isCritical { return .denied }
        if !risk.level.isDangerous, let rule = SessionRule(request), sessionRules[session]?.contains(rule) == true {
            return .allowed
        }
        queues[session, default: []].append(Pending(request: request, risk: risk, since: date))
        return .queued
    }

    /// Removes the Richiesta `id` of `session` with `answer`; returns whether the call may run, `nil` if it was not
    /// waiting. "Per questa Sessione" becomes a permission only where it is offered; elsewhere it counts as Solo ora.
    mutating func answer(_ id: PermissionRequest.ID, in session: UUID, with answer: PermissionAnswer) -> Bool? {
        guard let pending = remove(id, in: session) else { return nil }
        if answer == .allowForSession, pending.allowsSessionRule, let rule = SessionRule(pending.request) {
            sessionRules[session, default: []].insert(rule)
        }
        return answer.allows
    }

    /// Removes the Richiesta `id` of `session`, which `claude` no longer waits for.
    @discardableResult
    mutating func withdraw(_ id: PermissionRequest.ID, in session: UUID) -> Pending? {
        remove(id, in: session)
    }

    /// Removes the Richieste of `session`: its turn is over.
    mutating func clear(_ session: UUID) {
        queues[session] = nil
    }

    /// Forgets `session` altogether, its permissions included.
    mutating func forget(_ session: UUID) {
        queues[session] = nil
        sessionRules[session] = nil
    }

    private mutating func remove(_ id: PermissionRequest.ID, in session: UUID) -> Pending? {
        guard let index = queues[session]?.firstIndex(where: { $0.id == id }) else { return nil }
        let pending = queues[session]?.remove(at: index)
        if queues[session]?.isEmpty == true { queues[session] = nil }
        return pending
    }
}

/// A permission "Per questa Sessione": the same tool on exactly the same command, file or site.
///
/// Never wider than what the user saw: no prefixes, no wildcards.
nonisolated struct SessionRule: Hashable {
    let tool: String
    let subject: String?

    /// The rule that `request` would give; `nil` when its subject is missing, so no rule could be exact.
    init?(_ request: PermissionRequest) {
        tool = request.tool
        switch request.tool {
        case "Bash": subject = request.command
        case "Edit", "Write", "MultiEdit", "NotebookEdit", "Read": subject = request.path
        case "WebFetch": subject = request.url.flatMap { URL(string: $0)?.host() }
        default: subject = request.tool.hasPrefix("mcp__") ? nil : request.command ?? request.path ?? request.url
        }
        if subject == nil && !request.tool.hasPrefix("mcp__") { return nil }
    }
}
