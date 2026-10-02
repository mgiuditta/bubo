import Foundation
import SQLite3

nonisolated extension SessionFiles {
    /// Reads the conversation `sessionID` from Bubo's copy (ADR 0006), the database the agent bridge writes through
    /// the SDK's `sessionStore`; the tool results, which the copy does not hold, from `toolResultsFolder`.
    ///
    /// The copy keeps each subagent under the subpath `subagents/agent-<id>`, with its metadata as a last line of
    /// type `agent_metadata`, as `claude` would write `agent-<id>.meta.json` beside it.
    ///
    /// - Returns: `nil` when the copy has no line of the conversation.
    /// - Throws: ``MirrorFailure`` when the database does not open or read.
    static func mirrored(_ sessionID: String, in database: URL, toolResultsFolder: URL?) throws(MirrorFailure)
        -> SessionFiles? {
        var connection: OpaquePointer?
        defer { sqlite3_close(connection) }
        guard FileManager.default.fileExists(atPath: database.path) else { return nil }
        guard sqlite3_open_v2(database.path, &connection, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw .unreadable
        }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let sql = "SELECT subpath, entry FROM entries WHERE session = ? ORDER BY subpath, seq"
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK else { throw .unreadable }
        // SQLITE_TRANSIENT: SQLite copies the text before the call returns.
        sqlite3_bind_text(statement, 1, sessionID, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

        var lines: [String: [String]] = [:]
        var metadata: [String: String] = [:]
        var step = sqlite3_step(statement)
        while step == SQLITE_ROW {
            let subpath = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? ""
            let entry = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
            if entry.contains("\"agent_metadata\""), let value = try? JSONValue.decoding(line: entry),
               value["type"]?.string == "agent_metadata", case var .object(fields) = value {
                fields["type"] = nil
                metadata[subpath] = try? JSONValue.object(fields).encodedLine()
            } else {
                lines[subpath, default: []].append(entry)
            }
            step = sqlite3_step(statement)
        }
        guard step == SQLITE_DONE else { throw .unreadable }
        guard let transcript = lines[""] else { return nil }

        var files = SessionFiles(transcript: transcript.map { $0 + "\n" }.joined())
        for (subpath, entries) in lines where !subpath.isEmpty {
            files.subagents[Self.fileName(of: subpath) + ".jsonl"] = entries.map { $0 + "\n" }.joined()
        }
        for (subpath, content) in metadata {
            files.subagentMetadata[Self.fileName(of: subpath) + ".meta.json"] = content
        }
        if let toolResultsFolder {
            let results = (try? FileManager.default.contentsOfDirectory(at: toolResultsFolder,
                                                                       includingPropertiesForKeys: nil)) ?? []
            for file in results {
                if let content = try? String(contentsOf: file, encoding: .utf8) {
                    files.toolResults[file.lastPathComponent] = content
                }
            }
        }
        return files
    }

    /// The copy of the conversations did not read.
    enum MirrorFailure: Error, Equatable {
        case unreadable
    }

    /// `subagents/agent-a1` → `agent-a1`: the subagent's files are named by the last part of its subpath.
    private static func fileName(of subpath: String) -> String {
        subpath.split(separator: "/").last.map(String.init) ?? subpath
    }
}
