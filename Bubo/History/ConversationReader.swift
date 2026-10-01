import Foundation
import os

/// One past conversation in the Cronologia window, read only: scrolled to the message found and highlighted, with ⌘G
/// to the next point that answers the search.
///
/// It reads the messages through the agent bridge, with `getSessionMessages` from `~/.claude` or from Bubo's copy; when
/// neither has the conversation any more, it shows what the Indice kept and says it cannot be resumed.
@Observable
final class ConversationReader {
    /// What the reader can show of the conversation.
    nonisolated enum Content: Equatable, Sendable {
        case loading
        /// Every message, from `~/.claude` or from Bubo's copy.
        case available
        /// Gone from both: only what the Indice kept, and it cannot be resumed.
        case unavailable
        /// The bridge did not answer; Riprova reads it again.
        case failed
    }

    /// How long the CLI keeps a transcript by default: past it a conversation resumes from Bubo's copy (ADR 0006).
    static let cliRetention: TimeInterval = 30 * 86_400

    /// The conversation shown, as the search found it.
    let result: ConversationResult
    /// The searched words, highlighted in the messages that answer.
    let words: [String]
    /// The agent's conversation `claude --resume` takes for a Sessione: the latest of its turns; `nil` for the
    /// Cronologia CLI, which the terminal already lists.
    let resumeID: String?

    private(set) var content = Content.loading
    private(set) var lines: [TranscriptLine] = []
    /// The point shown now: the message found, then the one ⌘G jumped to.
    private(set) var current: TranscriptLine.ID?
    /// The message the scroll view keeps in view; set without animation, so the reader jumps and never scrolls.
    var position: TranscriptLine.ID?

    /// Reads every message of a conversation from `~/.claude` or Bubo's copy; empty when neither has it.
    @ObservationIgnored private let read: (String) async throws -> [CLIConversation.Message]
    /// Reads the messages of a conversation the Indice kept.
    @ObservationIgnored private let indexed: (String) async throws -> [CLIConversation.Message]

    init(result: ConversationResult, words: [String], resumeID: String?,
         read: @escaping (String) async throws -> [CLIConversation.Message],
         indexed: @escaping (String) async throws -> [CLIConversation.Message]) {
        self.result = result
        self.words = words
        self.resumeID = resumeID
        self.read = read
        self.indexed = indexed
    }

    /// The command that resumes the Sessione in a terminal, which does not list the conversations of the SDK.
    var resumeCommand: String? {
        resumeID.map { "claude --resume \($0)" }
    }

    /// The points that answer the search, in order: the message found and every message with a searched word.
    var matches: [TranscriptLine.ID] {
        let found = result.best?.message?.id
        return lines.filter { line in
            line.id == found || !MatchHighlight.ranges(in: line.message.text, matching: words).isEmpty
        }.map(\.id)
    }

    /// Whether the conversation last changed longer ago than the CLI keeps it, seen at `now`: it resumes from Bubo's
    /// copy, without the file history.
    func isPastCLIRetention(at now: Date) -> Bool {
        guard content == .available else { return false }
        let lastChange = lines.compactMap(\.message.date).max() ?? result.date
        return now.timeIntervalSince(lastChange) > Self.cliRetention
    }

    /// Reads the conversation and jumps to the message found, or to its end when nothing was searched.
    func load() async {
        content = .loading
        do {
            let messages = try await read(result.conversation)
            guard !Task.isCancelled else { return }
            if messages.isEmpty {
                lines = TranscriptLine.lines(of: await kept())
                content = .unavailable
            } else {
                lines = TranscriptLine.lines(of: messages)
                content = .available
            }
        } catch is CancellationError {
            return
        } catch {
            Logger.history.error("Conversation not read: \(String(describing: error), privacy: .private)")
            content = .failed
            return
        }
        let found = result.best?.message?.id
        current = lines.first { $0.id == found }?.id ?? matches.first ?? lines.last?.id
        position = current
    }

    /// Jumps to the next point that answers the search, back to the first after the last: ⌘G.
    func showNextMatch() {
        let matches = matches
        guard !matches.isEmpty else { return }
        let next = current.flatMap(matches.firstIndex(of:)).map { ($0 + 1) % matches.count } ?? 0
        current = matches[next]
        position = current
    }

    /// What the Indice kept of the conversation; the message found, at least.
    private func kept() async -> [CLIConversation.Message] {
        let kept: [CLIConversation.Message]
        do {
            kept = try await indexed(result.conversation)
        } catch {
            Logger.history.error("Indice not read: \(String(describing: error), privacy: .private)")
            kept = []
        }
        guard kept.isEmpty, let best = result.best else { return kept }
        return [CLIConversation.Message(id: best.message?.id, isFromUser: best.message?.isFromUser ?? false,
                                        text: best.text, date: best.message?.date)]
    }
}

extension Logger {
    nonisolated static let history = Logger(subsystem: "com.mgiuditta.bubo", category: "history")
}
