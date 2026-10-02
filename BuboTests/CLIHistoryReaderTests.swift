import Foundation
import SQLite3
import Testing
@testable import Bubo

struct CLIHistoryReaderTests {
    static let session = "6f1c2a40-7d3e-4b8a-9c11-2f0e5d9b7a10"
    static let otherSession = "0a9b8c7d-6e5f-4a3b-8c2d-1e0f9a8b7c6d"

    /// A transcript line of an answer, as Claude Code writes it.
    static func answer(_ message: String, request: String?, output: Int, at timestamp: String,
                       session: String = session, entrypoint: String = "cli", model: String = "claude-sonnet-4-5",
                       input: Int = 10, cacheRead: Int = 0, cacheWrite: Int = 0, cacheWrite1h: Int = 0,
                       uuid: String = UUID().uuidString) -> String {
        let request = request.map { #""requestId":"\#($0)","# } ?? ""
        return #"{"type":"assistant","sessionId":"\#(session)","timestamp":"\#(timestamp)","cwd":"/tmp/progetto","#
            + #"\#(request)"uuid":"\#(uuid)","entrypoint":"\#(entrypoint)","message":{"id":"\#(message)","#
            + #""model":"\#(model)","role":"assistant","content":[{"type":"text","text":"ok"}],"usage":{"#
            + #""input_tokens":\#(input),"output_tokens":\#(output),"cache_read_input_tokens":\#(cacheRead),"#
            + #""cache_creation_input_tokens":\#(cacheWrite),"cache_creation":{"ephemeral_5m_input_tokens":"#
            + #"\#(cacheWrite - cacheWrite1h),"ephemeral_1h_input_tokens":\#(cacheWrite1h)}}}}"#
    }

    static let userLine = #"{"type":"user","sessionId":"\#(session)","timestamp":"2026-09-30T10:00:00.000Z","#
        + #""message":{"role":"user","content":[{"type":"tool_result","content":"usage"}]}}"#

    static let prices = AnthropicPriceTable(date: Date(timeIntervalSince1970: 1_790_000_000), models: [
        "claude-sonnet-4-5": .init(input: 3, output: 15, cacheRead: Decimal(string: "0.3")!,
                                   cacheWrite5m: Decimal(string: "3.75")!, cacheWrite1h: 6),
    ])

    /// A folder like `~/.claude/projects` holding `files`, each a list of lines.
    static func projects(_ files: [String: [String]]) throws -> URL {
        let folder = URL.temporaryDirectory.appending(path: "projects-\(UUID().uuidString)", directoryHint: .isDirectory)
        for (path, lines) in files {
            let file = folder.appending(path: path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: file)
        }
        return folder
    }

    /// A copy like the bridge's database, with `lines` of `session`, marked as Cronologia CLI when `imported`.
    static func copy(_ lines: [String], session: String = session, imported: Bool = true) throws -> URL {
        let file = URL.temporaryDirectory.appending(path: "copy-\(UUID().uuidString).sqlite")
        var connection: OpaquePointer?
        defer { sqlite3_close(connection) }
        try #require(sqlite3_open(file.path, &connection) == SQLITE_OK)
        var sql = """
            CREATE TABLE entries (seq INTEGER PRIMARY KEY AUTOINCREMENT, project TEXT NOT NULL, session TEXT NOT NULL,
                subpath TEXT NOT NULL DEFAULT '', uuid TEXT, entry TEXT NOT NULL, mtime INTEGER NOT NULL);
            CREATE TABLE imported (session TEXT PRIMARY KEY, mtime INTEGER NOT NULL);
            """
        for line in lines {
            sql += "INSERT INTO entries (project, session, entry, mtime) VALUES ('p', '\(session)', '\(line)', 0);"
        }
        if imported { sql += "INSERT INTO imported VALUES ('\(session)', 0);" }
        try #require(sqlite3_exec(connection, sql, nil, nil, nil) == SQLITE_OK)
        return file
    }

    @Test func duplicateAndParallelLinesCountEachAnswerOnceWithItsLastLine() throws {
        // Answer A streams in three lines; answer B runs in parallel, interleaved; A's subagent repeats nothing.
        let projects = try Self.projects([
            "-tmp-progetto/\(Self.session).jsonl": [
                Self.answer("msg_A", request: "req_A", output: 1, at: "2026-09-30T10:00:01.000Z"),
                Self.answer("msg_B", request: "req_B", output: 3, at: "2026-09-30T10:00:01.500Z"),
                Self.userLine,
                Self.answer("msg_A", request: "req_A", output: 5, at: "2026-09-30T10:00:02.000Z"),
                Self.answer("msg_B", request: "req_B", output: 30, at: "2026-09-30T10:00:02.500Z"),
                Self.answer("msg_A", request: "req_A", output: 20, at: "2026-09-30T10:00:03.000Z"),
                "{not json",
            ],
            "-tmp-progetto/\(Self.session)/subagents/agent-1.jsonl": [
                Self.answer("msg_C", request: "req_C", output: 7, at: "2026-09-30T10:00:04.000Z"),
            ],
        ])
        let entries = CLIHistoryReader(projects: projects, prices: Self.prices).read()
        #expect(entries.count == 3)
        #expect(Set(entries.map(\.id)).count == 3)
        #expect(entries.map { $0.usage.models[0].outputTokens } == [30, 20, 7])
        #expect(entries.allSatisfy { $0.usage.unit == .rigaDiComando && $0.usage.mode == .commandLine })
        #expect(entries[1].project == URL(filePath: "/tmp/progetto", directoryHint: .isDirectory))
        #expect(entries[0].session == UUID(uuidString: Self.session))
    }

    @Test func bubosOwnTurnsAreLeftToTheLedger() throws {
        let projects = try Self.projects(["p/\(Self.session).jsonl": [
            Self.answer("msg_A", request: "req_A", output: 5, at: "2026-09-30T10:00:00.000Z", entrypoint: "sdk-ts"),
            Self.answer("msg_B", request: "req_B", output: 5, at: "2026-09-30T10:00:00.000Z", entrypoint: "sdk-cli"),
        ]])
        let entries = CLIHistoryReader(projects: projects).read()
        #expect(entries.map(\.id) == ["cli|msg_B|req_B"])
    }

    @Test func theCopyAndTheTranscriptsTogetherCountEachAnswerOnce() throws {
        let old = Self.answer("msg_old", request: "req_old", output: 9, at: "2026-06-01T08:00:00.000Z")
        let recent = Self.answer("msg_new", request: "req_new", output: 4, at: "2026-09-30T08:00:00.000Z")
        // The CLI has cleaned up the old conversation; Bubo's copy still has it, and the recent answer too.
        let database = try Self.copy([old, recent, Self.userLine])
        let projects = try Self.projects(["p/\(Self.session).jsonl": [recent]])
        let entries = CLIHistoryReader(database: database, projects: projects).read()
        #expect(entries.map(\.id) == ["cli|msg_old|req_old", "cli|msg_new|req_new"])
    }

    @Test func aCopyOfBubosSessioniIsNotTheCronologiaCLI() throws {
        let database = try Self.copy([Self.answer("msg_A", request: "req_A", output: 9, at: "2026-06-01T08:00:00.000Z")],
                                     imported: false)
        #expect(CLIHistoryReader(database: database).read().isEmpty)
    }

    @Test func withTheCopyOffOrMissingOnlyTheTranscriptsCount() throws {
        let projects = try Self.projects(["p/\(Self.session).jsonl": [
            Self.answer("msg_A", request: "req_A", output: 5, at: "2026-09-30T10:00:00.000Z"),
        ]])
        let missing = URL.temporaryDirectory.appending(path: "missing-\(UUID().uuidString).sqlite")
        #expect(CLIHistoryReader(database: missing, projects: projects).read().count == 1)
        #expect(!FileManager.default.fileExists(atPath: missing.path))
    }

    @Test func linesWithoutIdsCountOnTheirOwn() throws {
        let projects = try Self.projects(["p/\(Self.session).jsonl": [
            Self.answer("msg_A", request: nil, output: 5, at: "2026-09-30T10:00:00.000Z", uuid: "u1"),
            Self.answer("msg_A", request: nil, output: 6, at: "2026-09-30T10:00:01.000Z", uuid: "u2"),
        ]])
        #expect(CLIHistoryReader(projects: projects).read().count == 2)
    }

    @Test func theFigureIsAListEstimateWithTheHourLongCacheWritePricedApart() throws {
        let projects = try Self.projects(["p/\(Self.session).jsonl": [
            Self.answer("msg_A", request: "req_A", output: 1_000_000, at: "2026-09-30T10:00:00.000Z",
                        model: "claude-sonnet-4-5-20250929", input: 1_000_000, cacheRead: 1_000_000,
                        cacheWrite: 2_000_000, cacheWrite1h: 1_000_000),
        ]])
        let usage = try #require(CLIHistoryReader(projects: projects, prices: Self.prices).read().first?.usage)
        // 3 input + 15 output + 0.3 cache read + 3.75 five-minute write + 6 hour-long write.
        #expect(usage.cost == Decimal(string: "28.05"))
        #expect(usage.origin == .priceTable)
        #expect(usage.priceDate == Self.prices.date)
        #expect(usage.models[0].cacheWriteTokens == 2_000_000)
    }

    @Test func aModelMissingFromThePricesKeepsItsTokensWithNoFigure() throws {
        let projects = try Self.projects(["p/\(Self.session).jsonl": [
            Self.answer("msg_A", request: "req_A", output: 5, at: "2026-09-30T10:00:00.000Z", model: "claude-ignoto"),
        ]])
        let usage = try #require(CLIHistoryReader(projects: projects, prices: Self.prices).read().first?.usage)
        #expect(usage.cost == nil)
        #expect(usage.origin == .unpriced)
        #expect(usage.models[0].outputTokens == 5)
    }

    @Test func theBundledPricesHaveTheHourLongCacheWrite() throws {
        let prices = try #require(AnthropicPriceTable.bundled)
        let opus = try #require(prices.price(of: "claude-opus-5-5"))
        #expect(opus.cacheWrite1h == opus.input * 2)
    }

    @Test @MainActor func turnsCountOnTheirDayInTheMacsTimeZone() throws {
        // 23:30 in UTC on 30 September is already 1 October in Rome.
        let projects = try Self.projects(["p/\(Self.session).jsonl": [
            Self.answer("msg_A", request: "req_A", output: 5, at: "2026-09-30T23:30:00.000Z"),
        ]])
        var rome = Calendar(identifier: .gregorian)
        rome.timeZone = try #require(TimeZone(identifier: "Europe/Rome"))
        let entries = CLIHistoryReader(projects: projects, prices: Self.prices).read()
        let history = CostHistory(entries: entries, grouping: .period, period: .all, calendar: rome)
        let day = try #require(history.rows.first?.date)
        #expect(rome.component(.day, from: day) == 1)
        #expect(rome.component(.month, from: day) == 10)
    }
}
