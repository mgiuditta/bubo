import Foundation
import os

/// The daily check of the plugins' updates, for every Marketplace and not only the official ones (spec 20,
/// Aggiornamenti).
///
/// Downloads again the Marketplaces' catalogs with `claude plugin marketplace update`, which changes no plugin, then
/// asks git where the git sources with no `version` and no `sha` point now. Which plugins have an update is computed
/// from the files at each reading of the Plugin window, by ``review(_:state:approving:)``.
nonisolated struct PluginUpdateChecker: Sendable {
    /// Runs `claude plugin marketplace update`, in the write queue.
    var cli: PluginCLI
    var folders: PluginFolders
    var store: PluginUpdateStore
    /// The commit `ref` (the default branch when `nil`) of the repository at `url` points to; `nil` when git
    /// cannot say, such as offline or for a private repository with no credentials.
    var remoteTip: @Sendable (_ url: String, _ ref: String?) async -> String?

    /// How often the check runs.
    static let interval: TimeInterval = 24 * 60 * 60

    /// The user's `claude` and git, with git that never asks for a password.
    static func live(store: PluginUpdateStore = .standard) -> PluginUpdateChecker {
        let environment = PluginListing.environment()
        return PluginUpdateChecker(cli: .live(environment: environment), folders: .current(), store: store) { url, ref in
            let runner = ProcessRunner.disclaimed(environment: environment)
            let arguments = ["ls-remote", "--", url] + [ref ?? "HEAD"]
            let output = try? await withThrowingTaskGroup { group in
                group.addTask { try await runner.run(URL(filePath: "/usr/bin/git"), arguments) }
                group.addTask {
                    try await Task.sleep(for: .seconds(30))
                    throw PluginCLIError.timedOut
                }
                defer { group.cancelAll() }
                return try await group.next()!
            }
            guard let output, output.exitCode == 0 else { return nil }
            return Self.commit(inLsRemote: output.standardOutput)
        }
    }

    /// Checks, when the last check started more than a day ago; one caller at a time.
    ///
    /// - Returns: Whether it checked.
    @discardableResult
    func checkIfDue(now: Date = .now) async -> Bool {
        guard store.claimCheck(at: now, interval: Self.interval) else { return false }
        await check()
        return true
    }

    /// Downloads again the Marketplaces' catalogs, then reads where the git sources of the installed plugins point.
    func check() async {
        do {
            let result = try await cli.perform(.updateMarketplaces, project: nil)
            if !result.succeeded {
                Logger.plugins.notice("claude plugin marketplace update failed: \(result.message, privacy: .public)")
            }
        } catch is CancellationError {
            return
        } catch {
            Logger.plugins.notice("claude plugin marketplace update not run: \(String(describing: error), privacy: .public)")
        }
        let snapshot = await PluginSnapshot.read(from: folders, project: nil)
        let remotes = Set(snapshot.plugins.filter { snapshot.everyInstalled.contains($0.id) && $0.version == nil && $0.revision.sha == nil }
            .compactMap(Self.remote(of:)))
        let remoteTip = remoteTip
        var tips: [String: String] = [:]
        await withTaskGroup(of: (String, String?).self) { group in
            for remote in remotes {
                group.addTask { (remote.key, await remoteTip(remote.url, remote.ref)) }
            }
            for await (key, tip) in group {
                tips[key] = tip
            }
        }
        guard !Task.isCancelled else { return }
        store.change { $0.tips = tips }
    }

    // MARK: Git sources

    /// A git repository and the branch or tag a source follows.
    struct Remote: Hashable, Sendable {
        let url: String
        let ref: String?

        /// The key of its commit in ``PluginUpdateStore/State/tips``.
        var key: String { "\(url)#\(ref ?? "HEAD")" }
    }

    /// The repository of `entry`'s git source, when it is one git can read safely: `https`, `ssh` or `git@`, so a
    /// URL in a `marketplace.json` never reaches git as an option or as a transport that runs a command.
    static func remote(of entry: PluginEntry) -> Remote? {
        let url: String
        switch entry.source {
        case let .github(repo): url = "https://github.com/\(repo).git"
        case let .url(address), let .gitSubdirectory(address, _): url = address
        default: return nil
        }
        guard ["https://", "ssh://", "git@"].contains(where: url.hasPrefix), !url.contains(where: \.isWhitespace),
              entry.revision.ref.map({ !$0.hasPrefix("-") }) ?? true
        else { return nil }
        return Remote(url: url, ref: entry.revision.ref)
    }

    /// The commit on the first line of `git ls-remote`.
    static func commit(inLsRemote output: String) -> String? {
        guard let first = output.split(whereSeparator: \.isNewline).first?.split(whereSeparator: \.isWhitespace).first
        else { return nil }
        let commit = String(first)
        return PluginUpdate.isCommit(commit) ? commit : nil
    }

    /// The commit the clone at `folder` has checked out, read from its `.git` files without running git.
    static func head(ofClone folder: URL) -> String? {
        let git = folder.appending(path: ".git", directoryHint: .isDirectory)
        guard let head = try? String(contentsOf: git.appending(path: "HEAD"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        else { return nil }
        guard head.hasPrefix("ref: ") else { return PluginUpdate.isCommit(head) ? head : nil }
        let ref = String(head.dropFirst("ref: ".count))
        guard !ref.contains("..") else { return nil }
        if let loose = try? String(contentsOf: git.appending(path: ref), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), PluginUpdate.isCommit(loose) {
            return loose
        }
        let packed = (try? String(contentsOf: git.appending(path: "packed-refs"), encoding: .utf8)) ?? ""
        for line in packed.split(whereSeparator: \.isNewline) where line.hasSuffix(" \(ref)") {
            let commit = String(line.prefix { $0 != " " })
            if PluginUpdate.isCommit(commit) { return commit }
        }
        return nil
    }

    // MARK: Reviewing a snapshot

    /// What a reading of the files says about updates.
    struct Review: Sendable, Equatable {
        /// The installed plugins with a newer version, by plugin.
        var updates: [PluginID: PluginUpdate] = [:]
        /// The plugins with code on the Mac not seen before: brought by an update Claude Code made on its own.
        var newCode: [PluginProblem] = []
        /// The code on the Mac to remember as seen, by plugin: of the plugins seen for the first time, and of the
        /// ones the user approved.
        var seen: [String: [String]] = [:]
    }

    /// The updates of the installed plugins of `snapshot`, and the code on the Mac each one has and `state` has not
    /// seen. Reads the Marketplaces' clones and the installed folders, off the main actor.
    ///
    /// - Parameter approving: The plugins whose code on the Mac the user approved, by updating them or with Ho visto:
    ///   remembered as seen, never Da sistemare.
    @concurrent static func review(_ snapshot: PluginSnapshot, state: PluginUpdateStore.State,
                                   approving: Set<PluginID> = []) async -> Review {
        var review = Review()
        var heads: [String: String?] = [:]
        for entry in snapshot.plugins where entry.isInstalled {
            let clone = snapshot.marketplace(named: entry.id.marketplace)?.installLocation
            var manifestVersion: String?
            var tip: String?
            if case let .relative(path) = entry.source, let clone {
                let folder = clone.appending(path: path, directoryHint: .isDirectory).standardizedFileURL
                if folder.path.hasPrefix(clone.standardizedFileURL.path) {
                    manifestVersion = Self.manifestVersion(at: folder)
                }
                if heads[clone.path] == nil { heads[clone.path] = .some(head(ofClone: clone)) }
                tip = heads[clone.path] ?? nil
            } else if let remote = remote(of: entry) {
                tip = state.tips[remote.key]
            }
            let key = entry.id.description
            review.updates[entry.id] = PluginUpdate.update(for: entry, manifestVersion: manifestVersion, tip: tip,
                                                           dismissed: state.dismissed[key])

            guard let folder = entry.installations.lazy.compactMap(\.installPath)
                .first(where: { FileManager.default.fileExists(atPath: $0.path) })
            else { continue }
            let executables = PluginInventory.reading(pluginAt: folder).components.filter(\.runsCode)
            let keys = executables.map(\.seenKey).sorted()
            guard let seen = state.seenExecutables[key], !approving.contains(entry.id) else {
                if state.seenExecutables[key] != keys { review.seen[key] = keys }
                continue
            }
            let new = executables.filter { !seen.contains($0.seenKey) }
            if !new.isEmpty { review.newCode.append(.newExecutableCode(entry.id, components: new)) }
        }
        return review
    }

    /// The `version` of the `plugin.json` of the plugin at `folder`; `nil` when it has none.
    static func manifestVersion(at folder: URL) -> String? {
        guard let data = try? Data(contentsOf: folder.appending(path: ".claude-plugin/plugin.json")),
              let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = manifest["version"] as? String, !version.isEmpty
        else { return nil }
        return version
    }

    /// The components of `latest` that run code on the Mac and `installed` does not have; `nil` when the latest
    /// version's components are unknown, which counts as possible new code.
    static func newExecutables(installed: PluginInventory?, latest: PluginInventory?) -> [PluginComponent]? {
        guard let latest else { return nil }
        let old = Set(installed?.components.map(\.seenKey) ?? [])
        return latest.components.filter { $0.runsCode && !old.contains($0.seenKey) }
    }
}

nonisolated extension PluginComponent {
    /// The key a component is remembered by: its kind and its name.
    var seenKey: String { "\(kind)/\(name)" }
}
