import CoreServices
import Foundation
import os

/// The Plugin window's state, owned by the window, so nothing runs while it is closed (spec 20).
///
/// Draws from the files first, so the first draw never waits for `claude`; then merges what
/// `claude plugin list --json --available` adds. Only reads: Bubo never writes in `~/.claude`.
@MainActor @Observable final class PluginCatalog {
    /// What the window shows; `nil` until the files are read.
    private(set) var snapshot: PluginSnapshot?
    /// Whether the last `claude plugin list` failed: the window then says it shows the files only.
    private(set) var isListingUnavailable = false
    /// The official Marketplace's components, when Claude Code's cache has them in a known format.
    private(set) var officialCache: OfficialCatalogCache?

    @ObservationIgnored let folders: PluginFolders
    @ObservationIgnored private let listing: PluginListing
    /// The words of `snapshot`'s plugins, replaced with it.
    @ObservationIgnored private var search = PluginSearch([])
    /// The last list from `claude`, merged into every later reading of the files.
    @ObservationIgnored private var list: PluginList?
    /// The readings started, so an older one never replaces a newer one.
    @ObservationIgnored private var readings = 0

    /// Creates a catalog of the plugins in `folders`, completed by `listing`.
    init(folders: PluginFolders = .current(), listing: PluginListing = .live()) {
        self.folders = folders
        self.listing = listing
    }

    /// Draws from the files, then asks `claude` in background, then reads again at each FSEvents change of
    /// `installed_plugins.json`, `known_marketplaces.json`, the Marketplaces' `marketplace.json` and the three
    /// settings, until the task is cancelled. Emits `pluginsFirstDraw` around the first snapshot.
    func follow(project: URL?) async {
        snapshot = nil
        list = nil
        isListingUnavailable = false
        let state = Signposts.beginInterval(.pluginsFirstDraw)
        await reload(project)
        Signposts.endInterval(.pluginsFirstDraw, state)
        await withDiscardingTaskGroup { group in
            group.addTask { await self.refreshListing(project) }
            group.addTask { await self.loadOfficialCache() }
            group.addTask { await self.watch(project) }
        }
    }

    /// The entries of `item`, or of every Marketplace grouped by Marketplace while `query` is not empty.
    ///
    /// The search is a prefix match on the words of name, display name, description, category and tags, without
    /// case and accents, like the Palette.
    func entries(in item: PluginSidebarItem, matching query: String) -> [PluginSection] {
        guard let snapshot else { return [] }
        if let found = search.matches(query) {
            let results = found.map { snapshot.plugins[$0] }
            return Dictionary(grouping: results, by: \.id.marketplace)
                .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
                .map { PluginSection(marketplace: $0.key, entries: $0.value) }
        }
        let withProblems = Set(snapshot.problems.map(\.plugin))
        let entries: [PluginEntry] = switch item {
        case .installed:
            snapshot.plugins.filter(\.isInstalled)
        case .toFix:
            snapshot.plugins.filter { withProblems.contains($0.id) }
        case let .marketplace(name):
            snapshot.plugins.filter { $0.id.marketplace == name }
        case .updates, .mcpServers:
            []
        }
        return entries.isEmpty ? [] : [PluginSection(marketplace: nil, entries: entries)]
    }

    // MARK: Reading

    private func reload(_ project: URL?) async {
        readings += 1
        let reading = readings
        var next = await PluginSnapshot.read(from: folders, project: project)
        if let list { next = next.merging(list, project: project) }
        let search = await PluginSearch.indexing(next.plugins)
        guard reading == readings, !Task.isCancelled else { return }
        self.search = search
        snapshot = next
    }

    private func refreshListing(_ project: URL?) async {
        do {
            list = try await listing.list()
            isListingUnavailable = false
            await reload(project)
        } catch is CancellationError {
            return
        } catch {
            Logger.plugins.info("Plugins not listed by claude: \(String(describing: error), privacy: .public)")
            isListingUnavailable = true
        }
    }

    private func loadOfficialCache() async {
        officialCache = await OfficialCatalogCache.read(from: folders)
    }

    /// Reads again at each change of the files the snapshot comes from, until the task is cancelled.
    private func watch(_ project: URL?) async {
        let claude = folders.userSettings.deletingLastPathComponent()
        let roots = [folders.root, claude] + (project.map { [$0] } ?? [])
        let settings = project.map { folders.projectSettings(of: $0) }
        let files = Set(([folders.installedPlugins, folders.knownMarketplaces, folders.userSettings]
                         + [settings?.shared, settings?.local].compactMap { $0 }).map { Self.normalized($0.path) })
        let marketplaces = Self.normalized(folders.marketplaces.path) + "/"
        let (changes, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        let watcher = Task(priority: .utility) {
            for await batch in FileEvents.batches(under: roots.map(\.path),
                                                  since: FSEventStreamEventId(kFSEventStreamEventIdSinceNow))
            where batch.needsRescan || batch.paths.contains(where: { path in
                let path = Self.normalized(path)
                return files.contains(path) || path.hasPrefix(marketplaces) && path.hasSuffix("/.claude-plugin/marketplace.json")
            }) {
                continuation.yield()
            }
        }
        defer {
            watcher.cancel()
            continuation.finish()
        }
        for await _ in changes {
            await reload(project)
        }
    }

    /// `path` without the `/private` FSEvents puts before `/var` and `/tmp`.
    nonisolated private static func normalized(_ path: String) -> String {
        for prefix in ["/private/var/", "/private/tmp/"] where path.hasPrefix(prefix) {
            return String(path.dropFirst("/private".count))
        }
        return path
    }
}
