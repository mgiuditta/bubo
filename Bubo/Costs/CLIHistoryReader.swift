import Foundation
import os
import SQLite3

/// Reads the turns of the Cronologia CLI for the Costi window: from Bubo's copy (ADR 0006), beyond the 30 days the CLI
/// keeps, and from what `~/.claude/projects` still holds (spec 18, #163).
///
/// Each turn counts once: the transcript writes an answer on several lines, one per block and again while it streams,
/// so lines are deduplicated by `message.id` + `requestId`, keeping the last. The figure is a list estimate with Bubo's
/// `AnthropicPriceTable`, in a unit of its own, because the transcript does not say whether the turn was paid with
/// the subscription or the API key. These turns never reach the CostLedger, so they stay out of the Budget.
nonisolated struct CLIHistoryReader: Sendable {
    /// The tokens of one answer, as the transcript counts them.
    struct Tokens: Equatable, Sendable {
        var input = 0
        var output = 0
        var cacheRead = 0
        /// Every cache write, of 5 minutes and of 1 hour.
        var cacheWrite = 0
        /// The 1-hour share of `cacheWrite`, priced higher.
        var cacheWrite1h = 0
        /// Already counted in `output`.
        var thinking = 0

        var isEmpty: Bool { input + output + cacheRead + cacheWrite == 0 }
    }

    /// The entry point of the TypeScript Agent SDK, which Bubo's bridge runs: its Sessioni and Domande are already in
    /// the CostLedger, so they are left out here. `claude -p` (`sdk-cli`) and the Python SDK (`sdk-py`) count, as
    /// they do in ccusage.
    static let buboEntryPoints: Set<String> = ["sdk-ts"]

    /// Bubo's copy of the conversations; `nil` or missing reads only `projects`.
    var database: URL?
    /// The CLI's transcripts, `~/.claude/projects`; `nil` reads only the copy.
    var projects: URL?
    /// The prices of the estimate; `nil` leaves every turn with its tokens only.
    var prices: AnthropicPriceTable?
    /// The entry points whose lines are not the Cronologia CLI.
    var excludedEntryPoints = buboEntryPoints

    /// The CLI's transcripts of the user, in `~/.claude/projects`.
    static var userProjects: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/projects", directoryHint: .isDirectory)
    }

    /// The turns of the Cronologia CLI, oldest first, read away from the main actor.
    @concurrent func entries() async -> [CostLedger.Entry] {
        read()
    }

    /// The turns of the Cronologia CLI, oldest first: the copy first, then the transcripts, so the latest line wins.
    func read() -> [CostLedger.Entry] {
        var tally = Tally(prices: prices, excludedEntryPoints: excludedEntryPoints)
        if let database { Self.readCopy(at: database) { tally.add($0) } }
        if let projects {
            for file in Self.transcripts(in: projects) {
                guard let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { continue }
                for line in data.split(separator: UInt8(ascii: "\n")) { tally.add(line) }
            }
        }
        return tally.entries
    }

    /// Every `.jsonl` under `folder`, subagents included.
    private static func transcripts(in folder: URL) -> [URL] {
        let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)
        return (files?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "jsonl" }
    }

    /// Reads the assistant lines of the Cronologia CLI in Bubo's copy, cut down in SQL to what a turn needs.
    private static func readCopy(at database: URL, line: (Data) -> Void) {
        var connection: OpaquePointer?
        defer { sqlite3_close(connection) }
        guard FileManager.default.fileExists(atPath: database.path),
              sqlite3_open_v2(database.path, &connection, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return }
        let sql = """
            SELECT json_object('type', entry->>'$.type', 'sessionId', entry->>'$.sessionId',
                               'timestamp', entry->>'$.timestamp', 'cwd', entry->>'$.cwd',
                               'requestId', entry->>'$.requestId', 'uuid', entry->>'$.uuid',
                               'entrypoint', entry->>'$.entrypoint',
                               'message', json_object('id', entry->>'$.message.id', 'model', entry->>'$.message.model',
                                                      'usage', entry->'$.message.usage'))
            FROM entries
            WHERE session IN (SELECT session FROM imported) AND instr(entry, '"usage"') > 0
              AND entry->>'$.type' = 'assistant'
            ORDER BY seq
            """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK else {
            // A copy made before the Cronologia CLI was copied has no `imported` table.
            Logger.costs.notice("Cronologia CLI copy unreadable: \(String(cString: sqlite3_errmsg(connection)))")
            return
        }
        var step = sqlite3_step(statement)
        while step == SQLITE_ROW {
            if let text = sqlite3_column_blob(statement, 0) {
                line(Data(bytes: text, count: Int(sqlite3_column_bytes(statement, 0))))
            }
            step = sqlite3_step(statement)
        }
        if step != SQLITE_DONE {
            Logger.costs.error("Cronologia CLI copy read in part: \(String(cString: sqlite3_errmsg(connection)))")
        }
    }
}

nonisolated extension CLIHistoryReader {
    /// The turns of the lines read so far, one per `message.id` + `requestId`, the last line of each.
    struct Tally {
        let prices: AnthropicPriceTable?
        let excludedEntryPoints: Set<String>
        private var turns: [String: CostLedger.Entry] = [:]

        private let decoder = JSONDecoder()

        init(prices: AnthropicPriceTable?, excludedEntryPoints: Set<String> = CLIHistoryReader.buboEntryPoints) {
            self.prices = prices
            self.excludedEntryPoints = excludedEntryPoints
        }

        /// The turns, oldest first.
        var entries: [CostLedger.Entry] {
            turns.values.sorted { ($0.date, $0.id) < ($1.date, $1.id) }
        }

        /// Counts the transcript line `line`, if it is an answer with tokens, in place of an earlier line of the same
        /// answer.
        mutating func add(_ line: Data) {
            // Most lines are messages without tokens or tool results: they are skipped before decoding.
            guard line.firstRange(of: Self.usageKey) != nil, line.firstRange(of: Self.assistantType) != nil,
                  let decoded = try? decoder.decode(Line.self, from: line), decoded.type == "assistant",
                  !excludedEntryPoints.contains(decoded.entrypoint ?? ""),
                  let session = decoded.sessionId.flatMap(UUID.init(uuidString:)),
                  let date = decoded.timestamp.flatMap(Self.date(of:)),
                  let message = decoded.message, let usage = message.usage else { return }
            let tokens = usage.tokens
            guard !tokens.isEmpty else { return }
            let model = message.model ?? "claude"
            let figure = prices?.price(of: model)?.figure(of: tokens)
            let modelTokens = TurnUsage.ModelTokens(
                model: model, inputTokens: tokens.input, outputTokens: tokens.output, cacheReadTokens: tokens.cacheRead,
                cacheWriteTokens: tokens.cacheWrite, thinkingTokens: tokens.thinking, cost: figure)
            let turn = TurnUsage(mode: .commandLine, cost: figure, basis: .list, isComplete: true, models: [modelTokens],
                                 origin: figure == nil ? .unpriced : .priceTable,
                                 priceDate: figure == nil ? nil : prices?.date)
            // A line without both ids cannot be matched to another: it counts on its own, as ccusage does.
            let key = if let id = message.id, let request = decoded.requestId { "\(id)|\(request)" }
                      else { decoded.uuid ?? UUID().uuidString }
            turns[key] = CostLedger.Entry(
                id: "cli|\(key)", session: session,
                project: decoded.cwd.map { URL(filePath: $0, directoryHint: .isDirectory) },
                provider: "Anthropic", date: date, usage: turn)
        }

        private static let usageKey = Data("\"usage\"".utf8)
        private static let assistantType = Data("\"assistant\"".utf8)

        private static func date(of timestamp: String) -> Date? {
            (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(timestamp))
                ?? (try? Date.ISO8601FormatStyle().parse(timestamp))
        }
    }

    /// The fields of a transcript line a turn needs.
    private struct Line: Decodable {
        struct Message: Decodable {
            var id: String?
            var model: String?
            var usage: Usage?
        }

        var type: String?
        var sessionId: String?
        var timestamp: String?
        var cwd: String?
        var requestId: String?
        var uuid: String?
        var entrypoint: String?
        var message: Message?
    }

    /// The `usage` of an answer, as the API writes it.
    private struct Usage: Decodable {
        struct CacheCreation: Decodable {
            var ephemeral1h: Int?

            enum CodingKeys: String, CodingKey {
                case ephemeral1h = "ephemeral_1h_input_tokens"
            }
        }

        struct OutputDetails: Decodable {
            var thinking: Int?

            enum CodingKeys: String, CodingKey {
                case thinking = "thinking_tokens"
            }
        }

        var input: Int?
        var output: Int?
        var cacheRead: Int?
        var cacheWrite: Int?
        var cacheCreation: CacheCreation?
        var outputDetails: OutputDetails?

        enum CodingKeys: String, CodingKey {
            case input = "input_tokens"
            case output = "output_tokens"
            case cacheRead = "cache_read_input_tokens"
            case cacheWrite = "cache_creation_input_tokens"
            case cacheCreation = "cache_creation"
            case outputDetails = "output_tokens_details"
        }

        var tokens: Tokens {
            Tokens(input: input ?? 0, output: output ?? 0, cacheRead: cacheRead ?? 0, cacheWrite: cacheWrite ?? 0,
                   cacheWrite1h: cacheCreation?.ephemeral1h ?? 0, thinking: outputDetails?.thinking ?? 0)
        }
    }
}
