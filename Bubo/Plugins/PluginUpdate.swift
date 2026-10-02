/// A newer version of an installed plugin, as Claude Code would compute it from the Marketplace entry (spec 20,
/// Aggiornamenti).
///
/// Claude Code takes the `version` of the plugin's `plugin.json`, then the `version` of the entry, then the source:
/// the commit for git, a fingerprint for an archive, `unknown` for npm, the hash of the output for a `command`
/// (docs, plugins/loading). Bubo sees the new `plugin.json` only for a relative source, already in the Marketplace's
/// clone: for a git source without `version` the commit says only that something changed, a possible update the CLI
/// may not make if the new manifest pins its `version`.
nonisolated struct PluginUpdate: Sendable, Equatable {
    /// How sure Bubo is that `claude plugin update` changes something.
    enum Certainty: Sendable, Equatable {
        /// The version the CLI computes differs from the installed one.
        case certain
        /// The git source moved, but the new `plugin.json` may still pin the installed version.
        case possible
    }

    let plugin: PluginID
    /// The scope `claude plugin update` names: the most specific one installed, as the CLI picks without `--scope`.
    let scope: PluginScope
    /// The version Claude Code would install: a `version`, or a commit.
    let version: String
    let certainty: Certainty

    /// The update of `entry`, when the version Claude Code would install differs from the installed one.
    ///
    /// - Parameters:
    ///   - manifestVersion: The `version` of the `plugin.json` in the Marketplace's clone, for a relative source.
    ///   - tip: The commit the source points to now: the clone's for a relative source, the remote's from
    ///     `git ls-remote` for a git source with no `version` and no `sha`.
    ///   - dismissed: The version `claude plugin update` already left as it was, which is not offered again.
    /// - Returns: `nil` when it is not installed, only the organization manages it, the versions match or cannot be
    ///   compared, or the source is one whose version nobody can predict (npm, archive, `command`).
    static func update(for entry: PluginEntry, manifestVersion: String? = nil, tip: String? = nil,
                       dismissed: String? = nil) -> PluginUpdate? {
        let order: [PluginScope] = [.local, .project, .user]
        guard let installation = order.lazy.compactMap({ scope in entry.installations.first { $0.scope == scope } }).first,
              let (version, certainty) = expectedVersion(of: entry, manifestVersion: manifestVersion, tip: tip),
              installation.version != nil || installation.gitCommitSha != nil,
              !matches(version, installation), version != dismissed
        else { return nil }
        return PluginUpdate(plugin: entry.id, scope: installation.scope, version: version, certainty: certainty)
    }

    /// The version Claude Code would install for `entry`, and how sure that is; `nil` when it cannot be predicted.
    static func expectedVersion(of entry: PluginEntry, manifestVersion: String?, tip: String?)
        -> (version: String, certainty: Certainty)? {
        switch entry.source {
        case .relative:
            if let version = manifestVersion ?? entry.version { return (version, .certain) }
            return tip.map { ($0, .certain) }
        case .github, .url, .gitSubdirectory:
            if let version = entry.version { return (version, .certain) }
            return (entry.revision.sha ?? tip).map { ($0, .possible) }
        case .npm, .archive, .command, .unknown:
            return nil
        }
    }

    /// Whether `installation` already has `version`: the same `version`, or the same commit, short or full.
    static func matches(_ version: String, _ installation: PluginInstallation) -> Bool {
        if installation.version == version { return true }
        guard isCommit(version) else { return false }
        let expected = version.lowercased()
        return [installation.gitCommitSha, installation.version].compactMap { $0?.lowercased() }.filter(isCommit)
            .contains { $0.hasPrefix(expected) || expected.hasPrefix($0) }
    }

    /// Whether `text` looks like a git commit, full or abbreviated.
    static func isCommit(_ text: String) -> Bool {
        (7...40).contains(text.count) && text.allSatisfy(\.isHexDigit)
    }

    /// The version as the window shows it: a commit cut to 7 characters, like git.
    var displayVersion: String {
        Self.isCommit(version) ? String(version.prefix(7)) : version
    }
}
