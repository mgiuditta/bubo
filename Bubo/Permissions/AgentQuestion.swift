import Foundation

/// The questions the agent asks the user with `AskUserQuestion`: 1–4 of them, each with 2–4 options, one or many
/// to choose, and always a written answer besides.
///
/// Every text comes from the model, cleaned by the bridge: shown verbatim, never trusted.
nonisolated struct AgentQuestion: Identifiable, Equatable, Sendable, Decodable {
    /// One question, with its options in the agent's order.
    struct Item: Equatable, Sendable, Decodable {
        /// An answer the agent proposes.
        struct Option: Equatable, Sendable, Decodable {
            /// The answer, in a few words.
            let label: String
            /// What choosing it means, if the agent says.
            var detail: String?
            /// What it would look like, such as a layout or a snippet, shown in monospace beside the options.
            var preview: String?

            private enum CodingKeys: String, CodingKey {
                case label, detail = "description", preview
            }
        }

        /// The question itself.
        let question: String
        /// A short tag for it, such as "Libreria".
        let header: String
        let options: [Option]
        /// Whether more than one option may be chosen.
        let allowsMultiple: Bool
        /// Whether a written answer is accepted, under «Altro»: always for Claude, not when Copilot rules it out.
        var allowsText = true

        private enum CodingKeys: String, CodingKey {
            case question, header, options, allowsMultiple = "multiSelect", allowsText = "freeform"
        }
    }

    /// The user's answer to one question: the options chosen, by position, and what they wrote.
    struct Reply: Equatable, Sendable {
        var options: [Int] = []
        var text = ""

        /// Whether it answers `item`: a written answer where one is accepted, or exactly one option, or at least one
        /// when many are allowed.
        func answers(_ item: Item) -> Bool {
            if item.allowsText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
            return item.allowsMultiple ? !options.isEmpty : options.count == 1
        }
    }

    /// The bridge's id of the questions, which their answer carries back.
    let id: String
    let items: [Item]

    private enum CodingKeys: String, CodingKey {
        case id = "request", items = "questions"
    }

    /// Whether `replies` answer every question, in order.
    func isAnswered(by replies: [Reply]) -> Bool {
        replies.count == items.count && zip(replies, items).allSatisfy { $0.answers($1) }
    }
}

extension AgentQuestion.Item {
    /// Decodes a question from the bridge, where `freeform` is there only to rule a written answer out.
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        question = try container.decode(String.self, forKey: .question)
        header = try container.decode(String.self, forKey: .header)
        options = try container.decode([Option].self, forKey: .options)
        allowsMultiple = try container.decode(Bool.self, forKey: .allowsMultiple)
        allowsText = try container.decodeIfPresent(Bool.self, forKey: .allowsText) ?? true
    }
}
