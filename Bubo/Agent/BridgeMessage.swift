import Foundation

/// The JSON-lines protocol between Bubo and the agent bridge (`bridge/src/main.ts`).
///
/// Every line carries `v`; both sides refuse a version they do not speak.
enum BridgeProtocol {
    /// The version both sides speak.
    static let version = 1
}

/// A command Bubo writes to the bridge, one JSON object per line.
enum BridgeCommand: Equatable {
    /// Starts a conversation with `claude` in `directory`, answering `prompt`.
    case ask(id: String, prompt: String, directory: URL)
    /// Interrupts the conversation `id`.
    case cancel(id: String)

    /// The command as one line of JSON, newline included.
    func line() throws -> Data {
        var fields: [String: String] = [:]
        switch self {
        case let .ask(id, prompt, directory):
            fields = ["type": "ask", "id": id, "prompt": prompt, "cwd": directory.path]
        case let .cancel(id):
            fields = ["type": "cancel", "id": id]
        }
        var object: [String: Any] = fields
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
    /// A line in a protocol version Bubo does not speak.
    case unsupportedVersion(Int)

    private enum CodingKeys: String, CodingKey {
        case v, type, id, text, message
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
        case let type:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown event \(type)")
        }
    }
}
