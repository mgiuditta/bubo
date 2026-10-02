import Foundation

/// One message in the Cronologia window, with an id that stays the same while the conversation is shown.
nonisolated struct TranscriptLine: Identifiable, Equatable, Sendable {
    /// The message's id in its conversation, or its position when the bridge did not send one.
    let id: String
    let message: CLIConversation.Message

    /// The messages of a conversation, in order.
    static func lines(of messages: [CLIConversation.Message]) -> [TranscriptLine] {
        messages.enumerated().map { position, message in
            TranscriptLine(id: message.id ?? "#\(position)", message: message)
        }
    }
}
