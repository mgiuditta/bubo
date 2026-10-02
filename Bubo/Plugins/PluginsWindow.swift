import SwiftUI

/// The Plugin window, from the Finestra menu and the Palette: the plugins of every Marketplace, the installed
/// ones, and what needs attention; install, turn on and off, uninstall (spec 20, building steps 1 and 2).
///
/// Three columns: sidebar, list, detail; one search over every Marketplace. Bubo never writes in `~/.claude`: every
/// change is a `claude plugin …` command.
struct PluginsWindow: View {
    /// The id of the window's scene.
    static let windowID = "plugin"

    /// The Sessioni, for their Progetti; `nil` when they are unavailable.
    let store: SessionStore?
    @State private var catalog: PluginCatalog
    @State private var project: URL?
    @State private var attempt = 0
    @State private var selection: PluginSidebarItem?
    /// Whether the user chose a sidebar item: until then, Da sistemare is chosen as soon as it has something.
    @State private var hasChosen = false
    private let route = PluginsWindowRoute.shared
    @State private var plugin: PluginID?
    @State private var query = ""
    @State private var isChoosingFolder = false
    @State private var installing: PluginEntry?
    @State private var uninstalling: PluginEntry?
    @State private var isAddingMarketplace = false
    @State private var removingMarketplace: Marketplace?
    /// The source of the Marketplace being added in one click, and what went wrong with it.
    @State private var addingSource: String?
    @State private var addFailure: Text?
    @State private var showsAddFailure = false

    /// Creates the window, on the most recent Progetto of `store`.
    init(store: SessionStore?) {
        self.store = store
        _project = State(initialValue: store?.projects.first)
        var configuration: (@MainActor (URL) async throws -> ClaudeConfiguration)?
        if let store {
            // Never from the `claude` kept ready: started before a login, it would still say the server needs it.
            configuration = { project in try await store.currentConfiguration(of: project) }
        }
        _catalog = State(initialValue: PluginCatalog(reconnect: { store?.reconnectMCPServer(named: $0) },
                                                     configuration: configuration))
    }

    /// What the plugins are read for: the Progetto, and Riprova.
    private struct LoadKey: Equatable {
        var project: URL?
        var attempt: Int
    }

    /// The plugins `claude` failed to load.
    private var failing: Set<PluginID> {
        Set(catalog.snapshot?.problems.compactMap { if case let .loadFailed(id, _, _) = $0 { id } else { nil } } ?? [])
    }

    var body: some View {
        NavigationSplitView {
            PluginSidebar(snapshot: catalog.snapshot, project: project,
                          serversNeedingAuthentication: catalog.serversNeedingAuthentication.count,
                          selection: chosenSelection, addingSource: addingSource) {
                isChoosingFolder = true
            } add: { source in
                add(source)
            } addOther: {
                isAddingMarketplace = true
            } remove: { marketplace in
                removingMarketplace = marketplace
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 220)
        } content: {
            Group {
                if selection == .mcpServers, query.isEmpty {
                    serverList(catalog.servers)
                } else {
                    pluginList
                }
            }
            .navigationSplitViewColumnWidth(min: 300, ideal: 380)
        } detail: {
            if let snapshot = catalog.snapshot, let entry = snapshot.plugins.first(where: { $0.id == plugin }) {
                PluginDetail(entry: entry, problems: snapshot.problems.filter { $0.plugin == entry.id }, snapshot: snapshot,
                             marketplace: snapshot.marketplace(named: entry.id.marketplace),
                             officialCache: catalog.officialCache, catalog: catalog) {
                    installing = entry
                } uninstall: {
                    uninstalling = entry
                }
                .id(entry.id)
            } else {
                ContentUnavailableView("Scegli un plugin", systemImage: "puzzlepiece.extension")
            }
        }
        .searchable(text: $query, placement: .toolbar, prompt: "Cerca plugin")
        .frame(minWidth: 820, idealWidth: 1000, minHeight: 480, idealHeight: 640)
        .task(id: LoadKey(project: project, attempt: attempt)) { await catalog.follow(project: project) }
        .onChange(of: catalog.snapshot.map {
            PluginSidebarItem.initialSelection(in: $0, serversNeedingAuthentication: catalog.serversNeedingAuthentication.count)
        }) { _, initial in
            // The errors of `claude` and of the Sessioni arrive after the files: Da sistemare until the user chooses.
            if let initial, !hasChosen, selection == nil || initial == .toFix {
                selection = initial
            }
        }
        .onChange(of: route.problemsProject, initial: true) { _, asked in
            guard asked != nil, let asked = route.takeProblemsProject() else { return }
            project = asked
            selection = .toFix
            hasChosen = false
        }
        .onChange(of: catalog.snapshot?.marketplaces.map(\.name)) { _, names in
            // A Marketplace removed while selected.
            if case let .marketplace(name) = selection, let names, !names.contains(name) {
                selection = .installed
            }
        }
        .sheet(item: $installing) { entry in
            InstallSheet(entry: entry, marketplace: catalog.snapshot?.marketplace(named: entry.id.marketplace),
                         officialCache: catalog.officialCache, hasProject: project != nil, catalog: catalog)
        }
        .sheet(item: $uninstalling) { entry in
            UninstallSheet(entry: entry, catalog: catalog)
        }
        .sheet(isPresented: $isAddingMarketplace) {
            AddMarketplaceSheet(catalog: catalog)
        }
        .sheet(item: $removingMarketplace) { marketplace in
            RemoveMarketplaceSheet(marketplace: marketplace, plugins: catalog.snapshot?.pluginsRemoved(with: marketplace) ?? [],
                                   catalog: catalog)
        }
        .alert("Non riesco ad aggiungere il marketplace", isPresented: $showsAddFailure, presenting: addFailure) { _ in
            Button("OK") {}
        } message: { failure in
            failure
        }
        .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
            if case let .success(folder) = result { project = folder }
        }
        .font(Typography.body(size: 13))
        // The Notte direction's graphite, like the Agenti window (ADR 0004).
        .containerBackground(Palette.ink, for: .window)
        .preferredColorScheme(.dark)
        // Last, so everything inside gets it: selection is lightness, not the system blue (design system).
        .tint(Palette.accent)
    }

    /// The plugins of the sidebar item, or the search results; in Da sistemare, the MCP servers waiting for a login
    /// come first.
    @ViewBuilder
    private var pluginList: some View {
        let sections = catalog.entries(in: selection ?? .installed, matching: query)
        let waiting = selection == .toFix && query.isEmpty ? catalog.serversNeedingAuthentication : []
        if sections.isEmpty, !waiting.isEmpty {
            serverList(waiting)
        } else {
            PluginEntryList(sections: sections,
                            emptyTitle: selection == .installed || selection == nil ? "Nessun plugin installato" : "Nessun plugin",
                            isLoading: catalog.snapshot == nil, isSearching: !query.isEmpty,
                            isListingUnavailable: catalog.isListingUnavailable, failing: failing,
                            marketplaces: catalog.snapshot?.marketplaces ?? [],
                            officialCache: catalog.officialCache, selection: $plugin) { entry in
                installing = entry
            } retry: {
                attempt += 1
            }
            .safeAreaInset(edge: .top) {
                if !waiting.isEmpty {
                    MCPServerList(servers: waiting, catalog: catalog)
                        .padding(Spacing.small)
                }
            }
        }
    }

    /// `servers`, or what the window says without them.
    @ViewBuilder
    private func serverList(_ servers: [ClaudeConfiguration.MCPServer]) -> some View {
        if servers.isEmpty {
            ContentUnavailableView {
                Label("Nessun server MCP", systemImage: "server.rack")
            } description: {
                Text(store == nil || project == nil
                     ? "Scegli un Progetto per vedere i server MCP che Claude carica."
                     : "Claude non carica server MCP in questo Progetto.")
            }
        } else {
            ScrollView {
                MCPServerList(servers: servers, catalog: catalog)
                    .padding(Spacing.medium)
            }
        }
    }

    /// The sidebar's selection, remembering that the user chose.
    private var chosenSelection: Binding<PluginSidebarItem?> {
        Binding {
            selection
        } set: { item in
            selection = item
            hasChosen = true
        }
    }

    private func showAddFailure(_ failure: Text) {
        addFailure = failure
        showsAddFailure = true
    }

    /// Registers the Marketplace at `source` Per me, after the user's click on its row.
    private func add(_ source: String) {
        addingSource = source
        Task {
            defer { addingSource = nil }
            do {
                let result = try await catalog.perform(.addMarketplace(source: source, scope: .user))
                if !result.succeeded { showAddFailure(Text(marketplaceFailure: result)) }
            } catch is CancellationError {
                return
            } catch {
                showAddFailure(Text(marketplaceError: error))
            }
        }
    }
}

#Preview {
    PluginsWindow(store: nil)
}
