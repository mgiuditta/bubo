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

        private enum CodingKeys: String, CodingKey {
            case question, header, options, allowsMultiple = "multiSelect"
        }
    }

    /// The user's answer to one question: the options chosen, by position, and what they wrote.
    struct Reply: Equatable, Sendable {
        var options: [Int] = []
        var text = ""

        /// Whether it answers `item`: a written answer, or exactly one option, or at least one when many are allowed.
        func answers(_ item: Item) -> Bool {
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
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
