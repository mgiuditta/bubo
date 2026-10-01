import Foundation

/// What the agents of the Sessioni read and wrote, by Sessione, from the bridge's tool events (spec 11).
///
/// Paths are relative to the Progetto, so the same file has one star whichever copy the Sessione works in. Reads are
/// faint and short: only the latest ``litReads`` stay lit, the others are counted. Writes stay until the Sessione is
/// Fusa or Archiviata.
nonisolated struct GalaxyActivity: Equatable, Sendable {
    /// What one Sessione touched.
    struct Trace: Equatable, Sendable {
        /// The files written, in the order of their first write.
        var writes: [String] = []
        /// The files read lately, the latest last, at most ``GalaxyActivity/litReads``.
        var recentReads: [String] = []
        /// Every file read.
        var reads: Set<String> = []
        /// The files touched last, read or written, the latest last, at most ``GalaxyActivity/trailLength``: the
        /// comet's head and tail.
        var trail: [String] = []
    }

    /// The traces, by Sessione.
    private(set) var traces: [UUID: Trace] = [:]

    /// How many files the comet's tail goes through, its head included.
    static let trailLength = 6
    /// How many of a Sessione's latest reads stay lit on the map.
    static let litReads = 24

    /// Records that the Sessione `session` read `paths`, in this order.
    mutating func recordReads(_ paths: [String], by session: UUID) {
        guard !paths.isEmpty else { return }
        var trace = traces[session, default: Trace()]
        for path in paths {
            trace.reads.insert(path)
            Self.moveToEnd(path, in: &trace.recentReads, limit: Self.litReads)
            Self.moveToEnd(path, in: &trace.trail, limit: Self.trailLength)
        }
        traces[session] = trace
    }

    /// Records that the Sessione `session` wrote `path`.
    mutating func recordWrite(_ path: String, by session: UUID) {
        var trace = traces[session, default: Trace()]
        if !trace.writes.contains(path) { trace.writes.append(path) }
        Self.moveToEnd(path, in: &trace.trail, limit: Self.trailLength)
        traces[session] = trace
    }

    private static func moveToEnd(_ path: String, in paths: inout [String], limit: Int) {
        paths.removeAll { $0 == path }
        paths.append(path)
        if paths.count > limit { paths.removeFirst(paths.count - limit) }
    }

    /// `file`, an absolute path, relative to the first of `roots` it is in; `nil` when it is in none.
    static func relativePath(of file: String, in roots: [URL]) -> String? {
        for root in roots {
            let prefix = root.standardizedFileURL.path(percentEncoded: false)
            let folder = prefix.hasSuffix("/") ? prefix : prefix + "/"
            let path = URL(filePath: file).standardizedFileURL.path(percentEncoded: false)
            if path.hasPrefix(folder), path.count > folder.count { return String(path.dropFirst(folder.count)) }
        }
        return nil
    }
}
