import Foundation

/// A JSON value of any shape, for rewriting the lines of a `claude` transcript without knowing all their fields.
nonisolated enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case integer(Int64)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case let .bool(value): try container.encode(value)
        case let .integer(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        }
    }

    /// The value of `key`, when this is an object that has it.
    subscript(key: String) -> JSONValue? {
        guard case let .object(fields) = self else { return nil }
        return fields[key]
    }

    /// The text, when this is a string.
    var string: String? {
        guard case let .string(value) = self else { return nil }
        return value
    }

    /// The same value with every string, at any depth, passed through `transform`; keys stay as they are.
    func mappingStrings(_ transform: (String) -> String) -> JSONValue {
        switch self {
        case let .string(value): .string(transform(value))
        case let .array(values): .array(values.map { $0.mappingStrings(transform) })
        case let .object(fields): .object(fields.mapValues { $0.mappingStrings(transform) })
        case .null, .bool, .integer, .number: self
        }
    }

    /// Every string at any depth, in no particular order.
    var strings: [String] {
        switch self {
        case let .string(value): [value]
        case let .array(values): values.flatMap(\.strings)
        case let .object(fields): fields.values.flatMap(\.strings)
        case .null, .bool, .integer, .number: []
        }
    }

    /// Reads one line of a JSONL file.
    static func decoding(line: some StringProtocol) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(line.utf8))
    }

    /// The value as one line of JSON, with sorted keys and slashes as they are.
    func encodedLine() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }
}
