import Foundation

/// An action denied in a turn with nobody in front of it, as the bridge reports it: without its level, which Bubo
/// gives with `RiskClassifier`.
nonisolated struct BridgeDenial: Decodable, Equatable, Sendable {
    /// The `tool_use_id` of the call.
    let id: String
    let tool: String
    var command: String?
    var path: String?
    var url: String?
    /// The type of the subagent that called the tool, if any.
    var agent: String?
    /// The rules `claude` proposed to allow it, as `Tool(contenuto)`.
    var suggestions: [String] = []
    var source: Denial.Source

    private enum CodingKeys: String, CodingKey {
        case toolUseID, tool, command, path, url, agent, suggestions, source
    }

    init(id: String, tool: String, command: String? = nil, path: String? = nil, url: String? = nil, agent: String? = nil,
         suggestions: [String] = [], source: Denial.Source) {
        self.id = id
        self.tool = tool
        self.command = command
        self.path = path
        self.url = url
        self.agent = agent
        self.suggestions = suggestions
        self.source = source
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .toolUseID)
        tool = try container.decode(String.self, forKey: .tool)
        command = try container.decodeIfPresent(String.self, forKey: .command)
        path = try container.decodeIfPresent(String.self, forKey: .path)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        agent = try container.decodeIfPresent(String.self, forKey: .agent)
        suggestions = try container.decodeIfPresent([String].self, forKey: .suggestions) ?? []
        // A source Bubo does not know counts as `claude`'s.
        source = try container.decodeIfPresent(String.self, forKey: .source).flatMap(Denial.Source.init(rawValue:)) ?? .sdk
    }
}
