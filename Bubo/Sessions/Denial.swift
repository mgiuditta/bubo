import Foundation

/// An action denied in the turn of an Esecuzione, for its report.
nonisolated struct Denial: Codable, Hashable, Identifiable, Sendable {
    /// Who denied it.
    enum Source: String, Codable, Sendable {
        /// Bubo's gate: levels 4–5, writes outside the Sandbox, anything that would have asked.
        case gate
        /// `claude`: its rules, its mode, or nobody to ask.
        case sdk
    }

    /// The `tool_use_id` of the call.
    let id: String
    let tool: String
    var command: String?
    var path: String?
    var url: String?
    /// The Livello di rischio, from `RiskClassifier`, also for what `claude` denied.
    let level: RiskLevel
    /// The type of the subagent that called the tool, if any.
    var agent: String?
    /// The rules `claude` proposed to allow it, as they arrived: `Tool(contenuto)`.
    var suggestions: [String] = []
    let source: Source

    /// Whether "Consenti per questa Automazione" is offered: levels 1–3 only, with a pattern `claude` proposed.
    var allowsRule: Bool { level < .distruttivo && !suggestions.isEmpty }

    /// The command, file or address the call worked on.
    var subject: String? { command ?? path ?? url }

    /// The denial the bridge reported, with the level `classifier` gives it.
    init(_ reported: BridgeDenial, classifier: RiskClassifier) {
        id = reported.id
        tool = reported.tool
        command = reported.command
        path = reported.path
        url = reported.url
        agent = reported.agent
        suggestions = reported.suggestions
        source = reported.source
        let risk = classifier.risk(of: PermissionRequest(id: reported.id, tool: reported.tool, command: reported.command,
                                                         path: reported.path, url: reported.url))
        level = risk.isCritical ? .irreversibile : risk.level
    }
}

nonisolated extension RiskLevel: Codable {}
