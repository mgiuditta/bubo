import Foundation

/// Bubo's copy of the agent's conversations (ADR 0006): a SQLite database the agent bridge writes through the SDK's
/// `sessionStore`, and never cleans up by itself.
///
/// The Sessioni are copied as they go; the Cronologia CLI too, unless the user turns it off.
nonisolated enum ConversationStore {
    /// The setting that copies the Cronologia CLI as well; on by default.
    static let keepsCLIHistoryKey = "keepsCLIHistory"
    /// How often the Cronologia CLI is copied while Bubo runs: a conversation lands within a day of Bubo seeing it.
    static let refreshInterval = Duration.seconds(6 * 60 * 60)

    /// The database in Bubo's Application Support folder, which is created if missing.
    static func defaultFile() throws -> URL {
        let folder = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "Bubo", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "Conversazioni.sqlite")
    }

    /// The bytes the database at `file` takes on disk, its journal included; 0 when it does not exist yet.
    static func size(of file: URL) -> Int64 {
        [file.path, file.path + "-journal", file.path + "-wal"].reduce(0) { total, path in
            let size = try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64
            return total + (size ?? 0)
        }
    }
}
