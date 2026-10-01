import Foundation

/// What the user decided about the Risorse di squadra of each Progetto (ADR 0009): for each voce, the hash of the
/// text decided, who decided and when.
///
/// Kept in Bubo's Application Support folder, never in the repo: whoever writes the repo cannot accept for the user.
/// A decision is bound to the hash of the exact text, so a voce changed by one character is undecided again.
nonisolated struct TrustLedger: Sendable {
    /// What the user did with a voce.
    enum Decision: String, Codable, Sendable {
        /// It applies.
        case accepted
        /// It does not apply and is no longer to look at, until it changes.
        case ignored
    }

    /// A decision about one text of a voce.
    struct Entry: Codable, Equatable, Sendable {
        /// The SHA-256 of the normalized text (`TeamRules.hash(of:)`).
        var hash: String
        /// The normalized text, to show what changed since.
        var text: String
        var decision: Decision
        /// The user who decided.
        var decidedBy: String
        var decidedAt: Date
    }

    /// The JSON file, `[main checkout path: [Entry]]`.
    let file: URL

    /// The ledger in Bubo's Application Support folder.
    static let standard = TrustLedger(file: URL.applicationSupportDirectory.appending(path: "Bubo/Fiducia di squadra.json"))

    /// The decisions about the Progetto whose main checkout is `root`, oldest first; none when the file is unreadable.
    func entries(inProject root: String) -> [Entry] {
        (try? read())?[root] ?? []
    }

    /// The decision about exactly `rule` in the Progetto `root`, if any.
    func decision(about rule: String, inProject root: String) -> Decision? {
        let hash = TeamRules.hash(of: rule)
        return entries(inProject: root).last { $0.hash == hash }?.decision
    }

    /// Records `decision` about exactly `rule` in the Progetto `root`, replacing an earlier one about the same text.
    ///
    /// - Throws: A file error; an unreadable ledger is not overwritten.
    func record(_ decision: Decision, about rule: String, inProject root: String, by user: String = NSFullUserName(),
                at date: Date = .now) throws {
        var ledger = try read()
        let text = TeamRules.normalized(rule)
        let hash = TeamRules.hash(of: text)
        var entries = ledger[root] ?? []
        entries.removeAll { $0.hash == hash }
        entries.append(Entry(hash: hash, text: text, decision: decision, decidedBy: user, decidedAt: date))
        ledger[root] = entries
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(ledger).write(to: file, options: [.atomic])
    }

    private func read() throws -> [String: [Entry]] {
        let data: Data
        do {
            data = try Data(contentsOf: file)
        } catch CocoaError.fileReadNoSuchFile {
            return [:]
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([String: [Entry]].self, from: data)
    }
}
