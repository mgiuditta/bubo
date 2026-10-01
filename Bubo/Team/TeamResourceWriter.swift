import Foundation

/// Condividi con la squadra: adds a Regola del Progetto to `.bubo/regole.json` of the main checkout, where it shows in
/// the diff; the commit is the user's.
nonisolated struct TeamResourceWriter: Sendable {
    /// The Progetto's main checkout.
    let root: URL
    let ledger: TrustLedger

    /// Creates a writer for the Progetto `project`, or for the Progetto it is a worktree of.
    init(project: URL, ledger: TrustLedger = .standard) {
        root = URL(filePath: TrustGate.root(of: project), directoryHint: .isDirectory)
        self.ledger = ledger
    }

    /// The file it writes.
    var file: URL { root.appending(path: TeamRules.path) }

    /// Adds `rule` to the file's `allow`, unless it is there already, keeping the other rules; it counts as accepted
    /// by the user who shares it, if its level allows.
    ///
    /// - Throws: `TeamRulesError` when the file exists but cannot be read, or `.bubo` is not a real folder of the
    ///   Progetto; a file error otherwise. An unreadable file is never overwritten.
    func share(_ rule: String) throws {
        let rule = TeamRules.normalized(rule)
        guard ProjectRule.isWellFormed(rule) else { throw TeamRulesError.invalid }
        try checkFolder()
        var rules = try TeamRules.read(inProject: root) ?? TeamRules()
        if !rules.allow.contains(rule) {
            rules.allow.append(rule)
            try write(rules)
        }
        if !RiskClassifier(workingDirectory: root).risk(ofRule: rule).level.isDangerous {
            try ledger.record(.accepted, about: rule, inProject: root.path)
        }
    }

    /// Makes sure `.bubo` is a real folder of the Progetto, creating it if missing; a repo could ship it as a link.
    private func checkFolder() throws {
        let rootPath = TrustGate.realPath(root.path)
        guard rootPath != TrustGate.realPath(URL.homeDirectory.path) else { throw TeamRulesError.unsafeLocation }
        let folder = file.deletingLastPathComponent().path
        var status = stat()
        if lstat(folder, &status) != 0 {
            try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: false)
        } else if status.st_mode & S_IFMT != S_IFDIR {
            throw TeamRulesError.unsafeLocation
        }
        guard TrustGate.realPath(folder) == rootPath + "/.bubo" else { throw TeamRulesError.unsafeLocation }
    }

    /// Replaces the file atomically, readable by everyone like the other files of the repo.
    private func write(_ rules: TeamRules) throws {
        let object: [String: Any] = ["version": 1, "allow": rules.allow, "deny": rules.deny, "ask": rules.ask]
        let data = try JSONSerialization.data(withJSONObject: object,
                                              options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        let temporary = file.deletingLastPathComponent().appending(path: ".regole.json.bubo-\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: temporary.path, contents: data + Data("\n".utf8),
                                             attributes: [.posixPermissions: 0o644])
        else { throw CocoaError(.fileWriteUnknown) }
        guard rename(temporary.path, file.path) == 0 else {
            let code = errno
            unlink(temporary.path)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
    }
}
