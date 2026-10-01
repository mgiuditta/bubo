import Foundation

/// The JSON-lines protocol between Bubo and the agent bridge (`bridge/src/main.ts`).
///
/// Every line carries `v`; both sides refuse a version they do not speak.
enum BridgeProtocol {
    /// The version both sides speak.
    static let version = 3
}

/// A command Bubo writes to the bridge, one JSON object per line.
enum BridgeCommand: Equatable {
    /// Starts a conversation with `claude` in `directory`, answering `prompt`, loading only `settingSources`.
    ///
    /// When `directory` is a worktree, `projectConfigRoot` is its main checkout, where `claude` reads the
    /// Progetto's settings, `.mcp.json` and `.claude/`. `model` is an alias of `claude`, such as `sonnet`;
    /// without it, the model the user chose in `claude` answers.
    case ask(id: String, prompt: String, directory: URL, settingSources: [String], projectConfigRoot: URL? = nil,
             model: String? = nil)
    /// Interrupts the conversation `id`.
    case cancel(id: String)
    /// Answers the search `id` with the `cerca` tool's result.
    case found(id: String, text: String)
    /// Reads the Quota without a Domanda; the bridge answers with `quota` only if it has one.
    case readQuota

    /// The command as one line of JSON, newline included.
    func line() throws -> Data {
        var object: [String: Any]
        switch self {
        case let .ask(id, prompt, directory, settingSources, projectConfigRoot, model):
            object = ["type": "ask", "id": id, "prompt": prompt, "cwd": directory.path, "settingSources": settingSources]
            object["projectConfigRoot"] = projectConfigRoot?.path
            object["model"] = model
        case let .cancel(id):
            object = ["type": "cancel", "id": id]
        case let .found(id, text):
            object = ["type": "found", "id": id, "text": text]
        case .readQuota:
            object = ["type": "quota"]
        }
        object["v"] = BridgeProtocol.version
        var data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        data.append(0x0A)
        return data
    }
}

/// An event the bridge writes to Bubo, one JSON object per line.
enum BridgeEvent: Equatable, Decodable {
    /// The bridge is listening.
    case ready
    /// More of the answer to `id`.
    case text(id: String, text: String)
    /// The answer to `id` is complete.
    case done(id: String)
    /// The conversation `id`, or the bridge itself when `id` is `nil`, failed.
    case error(id: String?, message: String)
    /// The conversation `id` stopped at a subscription limit.
    case limit(id: String, reached: Quota.Limit)
    /// The conversation `id` stopped because the login of `claude` is no longer valid.
    case signInRequired(id: String)
    /// `claude` called `cerca`: search the Indice for `query`, only in the memory of `project` when given.
    case search(id: String, query: String, project: String?)
    /// The Quota windows `claude` reported; a window it did not report is `nil`.
    case quota(Quota)
    /// A line in a protocol version Bubo does not speak.
    case unsupportedVersion(Int)

    private enum CodingKeys: String, CodingKey {
        case v, type, id, text, message, query, project, fiveHour, sevenDay, window, resetsAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .v)
        guard version == BridgeProtocol.version else {
            self = .unsupportedVersion(version)
            return
        }
        switch try container.decode(String.self, forKey: .type) {
        case "ready": self = .ready
        case "text": self = .text(id: try container.decode(String.self, forKey: .id),
                                  text: try container.decode(String.self, forKey: .text))
        case "done": self = .done(id: try container.decode(String.self, forKey: .id))
        case "error": self = .error(id: try container.decodeIfPresent(String.self, forKey: .id),
                                    message: try container.decode(String.self, forKey: .message))
        case "limit": self = .limit(id: try container.decode(String.self, forKey: .id),
                                    reached: Quota.Limit(window: try container.decodeIfPresent(String.self, forKey: .window),
                                                        resetsAt: try container.decodeIfPresent(Double.self, forKey: .resetsAt)
                                                            .map(Date.init(timeIntervalSince1970:))))
        case "signInRequired": self = .signInRequired(id: try container.decode(String.self, forKey: .id))
        case "search": self = .search(id: try container.decode(String.self, forKey: .id),
                                      query: try container.decode(String.self, forKey: .query),
                                      project: try container.decodeIfPresent(String.self, forKey: .project))
        case "quota": self = .quota(Quota(fiveHour: try container.decodeIfPresent(Quota.Window.self, forKey: .fiveHour),
                                          sevenDay: try container.decodeIfPresent(Quota.Window.self, forKey: .sevenDay)))
        case let type:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown event \(type)")
        }
    }
}
