import Foundation
import os

/// The Plugin window's state, owned by the window, so nothing runs while it is closed (spec 20).
///
/// Draws from the files first, so the first draw never waits for `claude`; then merges what
/// `claude plugin list --json --available` adds. Bubo never writes in `~/.claude`: every change is a `claude plugin …`
/// command, after which the list is asked again, so the window shows what `claude` sees.
@MainActor @Observable final class PluginCatalog {
    /// What the window shows; `nil` until the files are read.
    private(set) var snapshot: PluginSnapshot?
    /// Whether the last `claude plugin list` failed: the window then says it shows the files only.
    private(set) var isListingUnavailable = false
    /// The official Marketplace's components, when Claude Code's cache has them in a known format.
    private(set) var officialCache: OfficialCatalogCache?
    /// The plugins with a command running or waiting its turn.
    private(set) var pending: Set<PluginID> = []
    /// The MCP servers `claude` loads in the Progetto followed, as last seen; empty without Sessioni.
    private(set) var servers: [ClaudeConfiguration.MCPServer] = []
    /// The installed plugins with a newer version in their Marketplace, by plugin.
    private(set) var updates: [PluginID: PluginUpdate] = [:]

    @ObservationIgnored let folders: PluginFolders
    @ObservationIgnored private let listing: PluginListing
    @ObservationIgnored private let cli: PluginCLI
    /// Reads the configuration `claude` loads in a folder, for the `plugin_errors` of its `system/init` and the
    /// status of its MCP servers; `nil` without Sessioni.
    @ObservationIgnored private let configuration: (@MainActor (URL) async throws -> ClaudeConfiguration)?
    @ObservationIgnored private let login: MCPLogin
    /// Has the turns in progress connect again to an MCP server, after a login.
    @ObservationIgnored private let reconnect: @MainActor (String) -> Void
    /// Tells the turns in progress that the plugins changed: a command that succeeded, or a change seen on disk.
    @ObservationIgnored private let pluginsDidChange: @MainActor () -> Void
    /// The last `plugin_errors` read, merged into every later reading of the files.
    @ObservationIgnored private var errors: [ClaudeConfiguration.PluginError] = []
    /// The main checkout of the Progetto followed, which the commands run in.
    @ObservationIgnored private var project: URL?
    /// The words of `snapshot`'s plugins, replaced with it.
    @ObservationIgnored private var search = PluginSearch([])
    /// The last list from `claude`, merged into every later reading of the files.
    @ObservationIgnored private var list: PluginList?
    /// The readings started, so an older one never replaces a newer one.
    @ObservationIgnored private var readings = 0
    /// What Bubo remembers about updates: the versions left as they were, the code on the Mac seen.
    @ObservationIgnored let updateStore: PluginUpdateStore
    /// The daily check, run when the window opens and the last one is more than a day old; `nil` for none.
    @ObservationIgnored private let updateChecker: PluginUpdateChecker?
    /// The plugins whose code on the Mac the user approved while their command runs: remembered, never Da sistemare.
    @ObservationIgnored private var approved: Set<PluginID> = []

    /// Creates a catalog of the plugins in `folders`, completed by `listing` and by the `plugin_errors` and MCP
    /// servers of the `configuration` of `claude`, and changed by `cli`; `login` logs in to an MCP server, after
    /// which `reconnect` tells the turns in progress; `pluginsDidChange` learns each change of the plugins.
    init(folders: PluginFolders = .current(), listing: PluginListing = .live(), cli: PluginCLI = .live(),
         login: MCPLogin = .live(), reconnect: @escaping @MainActor (String) -> Void = { _ in },
         pluginsDidChange: @escaping @MainActor () -> Void = {},
         configuration: (@MainActor (URL) async throws -> ClaudeConfiguration)? = nil,
         updateStore: PluginUpdateStore = .inMemory(), updateChecker: PluginUpdateChecker? = nil) {
        self.folders = folders
        self.updateStore = updateStore
        self.updateChecker = updateChecker
        self.listing = listing
        self.cli = cli
        self.login = login
        self.reconnect = reconnect
        self.pluginsDidChange = pluginsDidChange
        self.configuration = configuration
    }

    /// The MCP servers waiting for a login, which only `claude mcp login` can give.
    var serversNeedingAuthentication: [ClaudeConfiguration.MCPServer] {
        servers.filter(\.needsAuthentication)
    }

    /// The Progetto followed, as the commands see it: its main checkout.
    var followedProject: URL? { project }

    /// Draws from the files, then asks `claude` in background, then reads again at each FSEvents change of
    /// `installed_plugins.json`, `known_marketplaces.json`, the Marketplaces' `marketplace.json` and the three
    /// settings, until the task is cancelled. Emits `pluginsFirstDraw` around the first snapshot.
    ///
    /// A worktree counts as its main checkout, where `claude` records the installations of the Progetto.
    func follow(project: URL?) async {
        let project = project.map { cli.workingFolder(for: $0) }
        self.project = project
        snapshot = nil
        list = nil
        errors = []
        servers = []
        updates = [:]
        isListingUnavailable = false
        let state = Signposts.beginInterval(.pluginsFirstDraw)
        await reload(project)
        Signposts.endInterval(.pluginsFirstDraw, state)
        await withDiscardingTaskGroup { group in
            group.addTask { await self.refreshListing(project) }
            group.addTask { await self.refreshConfiguration(project) }
            group.addTask { await self.loadOfficialCache() }
            group.addTask { await self.watch(project) }
            group.addTask { await self.checkUpdatesIfDue(project) }
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
        case .updates:
            snapshot.plugins.filter { updates[$0.id] != nil }
        case .mcpServers:
            []
        }
        return entries.isEmpty ? [] : [PluginSection(marketplace: nil, entries: entries)]
    }

    // MARK: Writing

    /// Runs `command` with `claude` for the Progetto followed, then asks for the list again, whatever the outcome.
    ///
    /// - Returns: How it ended; a refusal of the CLI is a result, not an error.
    /// - Throws: `PluginCLIError`, or `CancellationError`.
    func perform(_ command: PluginCommand) async throws -> PluginCommandResult {
        let plugin = command.plugin
        if let plugin { pending.insert(plugin) }
        defer { if let plugin { pending.remove(plugin) } }
        let project = project
        let result: PluginCommandResult
        do {
            result = try await cli.perform(command, project: project)
        } catch {
            await refreshListing(project)
            throw error
        }
        // Before the list, so that Ricarica plugin shows at once (#212).
        if result.succeeded { pluginsDidChange() }
        await refreshListing(project)
        // A Sessione reads its errors only at its start, so they are read again, without holding up the window.
        Task { await refreshConfiguration(project) }
        return result
    }

    /// Runs the commands of `remedy` in order, stopping at the first that does not reach its goal.
    ///
    /// - Returns: How the last command run ended; success with no command.
    /// - Throws: `PluginCLIError`, or `CancellationError`.
    func fix(with remedy: PluginRemedy) async throws -> PluginCommandResult {
        var result = PluginCommandResult(succeeded: true)
        for command in remedy.commands {
            result = try await perform(command)
            guard result.succeeded else { break }
        }
        return result
    }

    /// The `userConfig` of `plugin` for the Progetto followed.
    ///
    /// - Throws: `PluginCLIError`, or `CancellationError`.
    func options(of plugin: PluginID) async throws -> PluginOptions {
        try await cli.options(of: plugin, project: project)
    }

    // MARK: Updates

    /// Updates the plugin of `update`, accepting the command the CLI showed when `accepting` is not `nil`.
    ///
    /// The code on the Mac of the new version counts as seen: the user approved it, in one click when it brought
    /// none, or in the Aggiorna sheet. When `claude` leaves the installed version as it was, the author did not change
    /// it: the update is not offered again until the Marketplace offers another version.
    ///
    /// - Throws: `PluginCLIError`, or `CancellationError`.
    func apply(_ update: PluginUpdate, accepting shown: PluginShownCommand? = nil) async throws -> PluginUpdateOutcome {
        let plugin = update.plugin
        let before = installedVersion(of: plugin, in: update.scope)
        approved.insert(plugin)
        defer { approved.remove(plugin) }
        let result = try await perform(.update(plugin, scope: update.scope, accepting: shown))
        if result.needsCommandConfirmation, let shown = result.shownCommand { return .needsConfirmation(shown) }
        guard result.succeeded else { return .failed(result) }
        await reload(project)
        let after = installedVersion(of: plugin, in: update.scope)
        let isUnchanged = after == before || result.message.contains("already at the latest version")
        updateStore.change { $0.dismissed[plugin.description] = isUnchanged ? update.version : nil }
        await reload(project)
        return isUnchanged ? .unchanged : .updated
    }

    /// Remembers the code on the Mac `plugin` has now as seen, as Ho visto asks: it leaves Da sistemare.
    func acknowledgeNewCode(of plugin: PluginID) async {
        approved.insert(plugin)
        defer { approved.remove(plugin) }
        await reload(project)
    }

    /// The version and commit of `plugin` installed in `scope`, as the files say.
    private func installedVersion(of plugin: PluginID, in scope: PluginScope) -> [String?] {
        let installation = snapshot?.plugins.first { $0.id == plugin }?.installations.first { $0.scope == scope }
        return [installation?.version, installation?.gitCommitSha]
    }

    private func checkUpdatesIfDue(_ project: URL?) async {
        guard let updateChecker, await updateChecker.checkIfDue() else { return }
        await reload(project)
    }

    // MARK: MCP servers

    /// Reads again the status of the MCP servers, as "Controlla" asks.
    func checkServers() async {
        await refreshConfiguration(project)
    }

    /// Runs `claude mcp login` for `server`; when it succeeds, the turns in progress connect again and the status is
    /// read again.
    ///
    /// - Returns: Whether the login succeeded; when it did not, the window shows the command to copy.
    /// - Throws: `CancellationError`.
    func logIn(to server: String) async throws -> Bool {
        let project = project
        guard try await login.logIn(to: server, in: cli.workingFolder(for: project)) else { return false }
        reconnect(server)
        await refreshConfiguration(project)
        return true
    }

    // MARK: Reading

    private func reload(_ project: URL?) async {
        readings += 1
        let reading = readings
        var next = await PluginSnapshot.read(from: folders, project: project)
        if let list { next = next.merging(list, project: project) }
        if !errors.isEmpty { next = next.merging(errors) }
        let review = await PluginUpdateChecker.review(next, state: updateStore.current, approving: approved)
        if !review.newCode.isEmpty { next = next.adding(review.newCode) }
        // What the files hold, also when a newer reading replaces this one: approvals must not get lost.
        if !review.seen.isEmpty {
            updateStore.change { $0.seenExecutables.merge(review.seen) { $1 } }
        }
        let search = await PluginSearch.indexing(next.plugins)
        guard reading == readings, !Task.isCancelled else { return }
        self.search = search
        updates = review.updates
        snapshot = next
    }

    private func refreshListing(_ project: URL?) async {
        do {
            list = try await listing.list(project)
            isListingUnavailable = false
            await reload(project)
        } catch is CancellationError {
            return
        } catch {
            Logger.plugins.info("Plugins not listed by claude: \(String(describing: error), privacy: .public)")
            isListingUnavailable = true
        }
    }

    private func refreshConfiguration(_ project: URL?) async {
        guard let project, let configuration else { return }
        do {
            let read = try await configuration(project)
            // The window may have moved to another Progetto meanwhile.
            guard project == self.project else { return }
            errors = read.pluginErrors
            servers = read.mcpServers
            await reload(project)
        } catch is CancellationError {
            return
        } catch {
            Logger.plugins.info("Plugin errors of the Sessioni not read: \(String(describing: error), privacy: .public)")
        }
    }

    private func loadOfficialCache() async {
        officialCache = await OfficialCatalogCache.read(from: folders)
    }

    /// Reads again at each change of the files the snapshot comes from, until the task is cancelled.
    private func watch(_ project: URL?) async {
        for await _ in folders.changes(in: project.map { [$0] } ?? [], includingMarketplaces: true) {
            pluginsDidChange()
            await reload(project)
        }
    }
}
