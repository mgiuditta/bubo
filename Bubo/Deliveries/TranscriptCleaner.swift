import Foundation

/// Cleans the files of a Sessione before a Consegna (spec 24, Pulizia): what identifies the sender, the reasoning and
/// the metadata outside the conversation go; paths become ``projectPlaceholder``; the secrets decided "Togli" become
/// ``secretPlaceholder``; the Sessione gets a new `sessionId`.
///
/// The transcript format is internal to `claude` and changes between versions, so every line goes through a table of
/// known types, at two levels: the line's `type` and, for `attachment`, the `attachment.type`. An unknown value at
/// either level stops the cleaning with ``Failure/unknownLineType(_:file:line:)``: nothing passes unread.
nonisolated struct TranscriptCleaner: Sendable {
    /// What the sender's worktree, home and their encoded forms become; at Avvia, the receiver's worktree.
    static let projectPlaceholder = "‹progetto›"
    /// What a removed secret, the account's email or its organization becomes.
    static let secretPlaceholder = "‹tolto›"

    /// Who sends the Sessione, and from where.
    struct Sender: Sendable {
        /// The worktree the Sessione ran in.
        var worktree: String
        /// The sender's home folder.
        var home: String
        /// The account's email, its organization's name and id: taken out wherever they appear.
        var identity: [String]
    }

    /// Why something left the Sessione, as the foglio di Consegna lists it under "Tolto da Bubo".
    enum Removal: String, CaseIterable, Sendable {
        /// The account's email and organization, the Mac's environment and the model's identity.
        case identity
        /// The system prompt the sender's `claude` built.
        case promptSnapshot
        /// Lines outside the conversation: titles, costs, queues, file history, progress.
        case metadata
        /// `thinking` and `redacted_thinking` blocks, which another account could not read anyway.
        case reasoning
    }

    /// What one line type, or one attachment type, becomes.
    enum Rule: Sendable {
        /// The line stays, rewritten.
        case keep
        /// The line goes; the lines after it hang from its parent.
        case remove(Removal)
    }

    /// The cleaning stopped.
    enum Failure: LocalizedError, Equatable {
        /// A line, or an attachment, of a type Bubo does not know yet.
        case unknownLineType(String, file: String, line: Int)
        /// A line that is not a JSON object.
        case unreadableLine(file: String, line: Int)

        var errorDescription: String? {
            String(localized: "Questa Sessione ha righe che Bubo non sa ancora ripulire.")
        }
    }

    /// What the cleaning gives back.
    struct Result: Equatable, Sendable {
        var files: SessionFiles
        /// The lines, or blocks for ``Removal/reasoning``, taken out for each reason, in every file.
        var removed: [Removal: Int]
        /// How many times a secret, the email or the organization became ``secretPlaceholder``.
        var replacedSecrets: Int
        /// The user and assistant lines left in the transcript, subagent apart.
        var messageCount: Int
    }

    /// The rule for each line type `claude` writes, as of 2.1.287.
    static let lineRules: [String: Rule] = [
        "user": .keep,
        "assistant": .keep,
        "system": .keep,
        "summary": .keep,
        "attachment": .keep,
        "pr-link": .remove(.metadata),
        "ai-title": .remove(.metadata),
        "custom-title": .remove(.metadata),
        "last-prompt": .remove(.metadata),
        "cost-state": .remove(.metadata),
        "queue-operation": .remove(.metadata),
        "atis-latch": .remove(.metadata),
        "progress": .remove(.metadata),
    ]

    /// The rule for each `attachment.type`.
    static let attachmentRules: [String: Rule] = {
        var rules: [String: Rule] = [
            "session_context": .remove(.identity),
            "credential_org": .remove(.identity),
            "environment": .remove(.identity),
            "model": .remove(.identity),
            "remote_session_change": .remove(.identity),
            "prompt_snapshot": .remove(.promptSnapshot),
            "prompt_render_point": .remove(.promptSnapshot),
            "deferred_tools_record": .remove(.promptSnapshot),
        ]
        let kept = [
            "instructions", "nested_memory", "relevant_memories", "skill_listing", "invoked_skills", "date", "language",
            "output_style", "output_style_instructions", "context_sections", "coordinator_context", "todo",
            "todo_reminder", "plan_mode", "plan_mode_exit", "plan_mode_reentry", "queued_command", "diagnostics",
            "mcp_resource", "command_permissions", "critical_system_reminder", "structured_output",
            "bash_output_audience_note", "unknown_command_fallback", "silent_turn_reminder", "token_usage",
            "budget_usd", "task_status", "max_turns_reached", "agent_mention", "new_file", "file", "edited_text_file",
            "edited_image_file", "directory", "compact_file_reference", "already_read_file", "selected_lines_in_ide",
            "selected_lines_in_diff", "opened_file_in_ide", "hook_success", "hook_additional_context",
            "hook_non_blocking_error", "hook_blocking_error", "hook_system_message", "hook_cancelled",
            "hook_stopped_continuation", "async_hook_response", "async_hook_response_batch",
        ]
        for type in kept { rules[type] = .keep }
        return rules
    }()

    private static let reasoningBlocks: Set<String> = ["thinking", "redacted_thinking"]
    private static let chainKeys = ["parentUuid", "logicalParentUuid", "leafUuid"]

    let sender: Sender
    let newSessionID: String
    let removedSecrets: Set<String>

    /// Creates a cleaner for `sender`'s Sessione, which becomes `newSessionID` and loses `removedSecrets`.
    init(sender: Sender, newSessionID: String, removedSecrets: Set<String> = []) {
        self.sender = sender
        self.newSessionID = newSessionID
        self.removedSecrets = removedSecrets
    }

    /// Returns `session` cleaned: every JSONL file line by line, the subagent metadata and the tool results.
    ///
    /// - Throws: ``Failure`` at the first line Bubo cannot clean.
    func cleaning(_ session: SessionFiles) throws(Failure) -> Result {
        let rewriter = Rewriter(
            sender: sender,
            sessionIDs: Self.sessionIDs(in: session.transcript),
            newSessionID: newSessionID,
            secrets: removedSecrets
        )
        var removed: [Removal: Int] = [:]
        let main = try cleaning(session.transcript, named: SessionFiles.transcriptName, with: rewriter, removed: &removed)
        var subagents: [String: String] = [:]
        for (name, content) in session.subagents {
            subagents[name] = try cleaning(content, named: name, with: rewriter, removed: &removed).text
        }
        var metadata: [String: String] = [:]
        for (name, content) in session.subagentMetadata {
            metadata[name] = try rewriter.rewritingJSON(content, file: name)
        }
        let toolResults = session.toolResults.mapValues { rewriter.rewriting($0) }
        return Result(
            files: SessionFiles(transcript: main.text, subagents: subagents, subagentMetadata: metadata,
                                toolResults: toolResults),
            removed: removed,
            replacedSecrets: rewriter.replacedSecrets,
            messageCount: main.messageCount
        )
    }

    /// The `parentUuid` links that point to no earlier line of the same JSONL file, by line number.
    static func brokenLinks(in jsonl: String) -> [Int] {
        var seen: Set<String> = []
        var broken: [Int] = []
        for (index, line) in jsonl.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
        where !line.isEmpty {
            guard let value = try? JSONValue.decoding(line: line) else { broken.append(index + 1); continue }
            if let parent = value["parentUuid"]?.string, !seen.contains(parent) { broken.append(index + 1) }
            if let uuid = value["uuid"]?.string { seen.insert(uuid) }
        }
        return broken
    }

    // MARK: Lines

    private func cleaning(_ jsonl: String, named file: String, with rewriter: Rewriter,
                          removed: inout [Removal: Int]) throws(Failure) -> (text: String, messageCount: Int) {
        // A removed line's uuid → its parent, so the next line hangs from what was above it.
        var bypass: [String: JSONValue] = [:]
        var lines: [String] = []
        var messageCount = 0
        for (index, text) in jsonl.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
        where !text.allSatisfy(\.isWhitespace) {
            guard let line = try? JSONValue.decoding(line: text), case var .object(fields) = line,
                  let type = fields["type"]?.string
            else { throw .unreadableLine(file: file, line: index + 1) }

            var rule = try Self.rule(for: line, type: type, file: file, line: index + 1)
            if case .keep = rule, type == "assistant", let content = line["message"]?["content"],
               case let .array(blocks) = content {
                let kept = blocks.filter { !Self.reasoningBlocks.contains($0["type"]?.string ?? "") }
                if kept.count < blocks.count { removed[.reasoning, default: 0] += blocks.count - kept.count }
                if kept.isEmpty, !blocks.isEmpty {
                    rule = .remove(.reasoning)
                } else if case var .object(message) = fields["message"] {
                    message["content"] = .array(kept)
                    fields["message"] = .object(message)
                }
            }

            for key in Self.chainKeys {
                if let parent = fields[key] { fields[key] = Self.resolved(parent, through: bypass) }
            }
            switch rule {
            case let .remove(reason):
                if reason != .reasoning { removed[reason, default: 0] += 1 }
                if let uuid = fields["uuid"]?.string { bypass[uuid] = fields["parentUuid"] ?? .null }
            case .keep:
                if type == "user" || type == "assistant" { messageCount += 1 }
                let cleaned = JSONValue.object(fields).mappingStrings(rewriter.rewriting)
                guard let encoded = try? cleaned.encodedLine() else { throw .unreadableLine(file: file, line: index + 1) }
                lines.append(encoded)
            }
        }
        return (lines.map { $0 + "\n" }.joined(), messageCount)
    }

    private static func rule(for line: JSONValue, type: String, file: String, line number: Int) throws(Failure) -> Rule {
        if type.hasPrefix("file-history-") { return .remove(.metadata) }
        guard let rule = lineRules[type] else { throw .unknownLineType(type, file: file, line: number) }
        guard type == "attachment" else { return rule }
        let attachment = line["attachment"]?["type"]?.string ?? ""
        guard let attachmentRule = attachmentRules[attachment] else {
            throw .unknownLineType("attachment/\(attachment)", file: file, line: number)
        }
        return attachmentRule
    }

    private static func resolved(_ parent: JSONValue, through bypass: [String: JSONValue]) -> JSONValue {
        var parent = parent
        while let uuid = parent.string, let above = bypass[uuid] { parent = above }
        return parent
    }

    private static func sessionIDs(in transcript: String) -> Set<String> {
        var ids: Set<String> = []
        for line in transcript.split(separator: "\n") where line.contains("\"sessionId\"") {
            if let id = (try? JSONValue.decoding(line: line))?["sessionId"]?.string { ids.insert(id) }
        }
        return ids
    }
}

// MARK: - Rewriting the strings

extension TranscriptCleaner {
    /// Rewrites every string of a cleaned file: secrets and identity first, then paths, then the `sessionId`.
    nonisolated private final class Rewriter {
        private let secrets: [String]
        private let paths: NSRegularExpression?
        private let sessionIDs: [String]
        private let newSessionID: String
        private(set) var replacedSecrets = 0

        init(sender: Sender, sessionIDs: Set<String>, newSessionID: String, secrets: Set<String>) {
            self.secrets = (secrets.union(sender.identity)).filter { !$0.isEmpty }.sorted { $0.count > $1.count }
            let folders = [sender.worktree, sender.home].filter { !$0.isEmpty && $0 != "/" }
            let needles = Set(folders + folders.map(ProjectMemory.folderName(ofRoot:))).sorted { $0.count > $1.count }
            let alternatives = needles.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
            // A path ends where a file name could not go on: `/Users/ada` is not in `/Users/adam`.
            paths = needles.isEmpty ? nil : try? NSRegularExpression(pattern: "(?:\(alternatives))(?![A-Za-z0-9_.-])")
            // Only ids long enough not to be found by chance inside other words.
            self.sessionIDs = sessionIDs.filter { $0 != newSessionID && $0.count >= 16 }.sorted()
            self.newSessionID = newSessionID
        }

        func rewriting(_ text: String) -> String {
            var text = text
            for secret in secrets where text.contains(secret) {
                let parts = text.components(separatedBy: secret)
                replacedSecrets += parts.count - 1
                text = parts.joined(separator: TranscriptCleaner.secretPlaceholder)
            }
            if let paths {
                text = paths.stringByReplacingMatches(
                    in: text, range: NSRange(text.startIndex..., in: text),
                    withTemplate: NSRegularExpression.escapedTemplate(for: TranscriptCleaner.projectPlaceholder)
                )
            }
            for id in sessionIDs where text.contains(id) {
                text = text.replacing(id, with: newSessionID)
            }
            return text
        }

        func rewritingJSON(_ text: String, file: String) throws(Failure) -> String {
            guard let value = try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)),
                  let encoded = try? value.mappingStrings(rewriting).encodedLine()
            else { throw .unreadableLine(file: file, line: 1) }
            return encoded
        }
    }
}
