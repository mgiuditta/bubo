import Foundation

/// One message of the Conversazione ripulita in the foglio di Consegna (spec 24): what goes out, with the parts Bubo
/// took out and the possible secrets marked. A secret never shows whole: only its masked excerpt.
nonisolated struct DeliveryPreviewLine: Identifiable, Equatable, Sendable {
    /// A piece of the message's text.
    enum Segment: Equatable, Sendable {
        /// Text that goes out as it is.
        case plain(String)
        /// A placeholder Bubo put in: `‹progetto›` or `‹tolto›`.
        case removed(String)
        /// A possible secret, by its finding's id.
        case secret(SecretScanner.Finding.ID)
    }

    /// The transcript line's `uuid`, which a finding's location points to.
    let id: String
    let isFromUser: Bool
    let segments: [Segment]

    /// The longest text shown for one message: the rest goes out, but the foglio stays light.
    static let characterLimit = 2_000

    /// The user and assistant messages of the cleaned transcript `jsonl`, with `findings` marked.
    static func lines(of jsonl: String, findings: [SecretScanner.Finding]) -> [DeliveryPreviewLine] {
        let needles = findings.map { ($0.value, Segment.secret($0.id)) }
            + [TranscriptCleaner.projectPlaceholder, TranscriptCleaner.secretPlaceholder].map { ($0, Segment.removed($0)) }
        return jsonl.split(separator: "\n").compactMap { text -> DeliveryPreviewLine? in
            guard let line = try? JSONValue.decoding(line: text), let type = line["type"]?.string,
                  type == "user" || type == "assistant", let id = line["uuid"]?.string
            else { return nil }
            let body = Self.text(of: line["message"]?["content"])
            guard !body.isEmpty else { return nil }
            return DeliveryPreviewLine(id: id, isFromUser: type == "user",
                                       segments: limited(segments(of: body, needles: needles)))
        }
    }

    /// `segments` cut after ``characterLimit`` characters of plain text; cut after the marking, so a secret is never
    /// shown in part.
    private static func limited(_ segments: [Segment]) -> [Segment] {
        var budget = characterLimit
        var kept: [Segment] = []
        for segment in segments {
            guard budget > 0 else { break }
            if case let .plain(text) = segment {
                kept.append(.plain(String(text.prefix(budget)) + (text.count > budget ? "…" : "")))
                budget -= text.count
            } else {
                kept.append(segment)
            }
        }
        return kept
    }

    /// The readable text of a message's content: its text, the tools it called with their input, their results.
    private static func text(of content: JSONValue?) -> String {
        switch content {
        case let .string(text):
            return text
        case let .array(blocks):
            return blocks.compactMap { block -> String? in
                switch block["type"]?.string {
                case "text": block["text"]?.string
                case "tool_use": "\(block["name"]?.string ?? "") \((try? block["input"]?.encodedLine()) ?? "")"
                case "tool_result": block["content"]?.strings.joined(separator: "\n")
                default: nil
                }
            }.joined(separator: "\n")
        default:
            return ""
        }
    }

    /// `text` cut at every needle, the earliest first and the longest at the same place.
    static func segments(of text: String, needles: [(String, Segment)]) -> [Segment] {
        var segments: [Segment] = []
        var rest = text[...]
        while !rest.isEmpty {
            var earliest: (range: Range<Substring.Index>, segment: Segment)?
            for (needle, segment) in needles where !needle.isEmpty {
                guard let range = rest.range(of: needle) else { continue }
                if let current = earliest, current.range.lowerBound < range.lowerBound
                    || (current.range.lowerBound == range.lowerBound && current.range.upperBound >= range.upperBound) {
                    continue
                }
                earliest = (range, segment)
            }
            guard let earliest else {
                segments.append(.plain(String(rest)))
                break
            }
            if earliest.range.lowerBound > rest.startIndex {
                segments.append(.plain(String(rest[..<earliest.range.lowerBound])))
            }
            segments.append(earliest.segment)
            rest = rest[earliest.range.upperBound...]
        }
        return segments
    }
}
