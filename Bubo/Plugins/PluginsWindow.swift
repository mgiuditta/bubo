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
    @State private var catalog = PluginCatalog()
    @State private var project: URL?
    @State private var attempt = 0
    @State private var selection: PluginSidebarItem?
    @State private var plugin: PluginID?
    @State private var query = ""
    @State private var isChoosingFolder = false
    @State private var installing: PluginEntry?
    @State private var uninstalling: PluginEntry?

    /// Creates the window, on the most recent Progetto of `store`.
    init(store: SessionStore?) {
        self.store = store
        _project = State(initialValue: store?.projects.first)
    }

    /// What the plugins are read for: the Progetto, and Riprova.
    private struct LoadKey: Equatable {
        var project: URL?
        var attempt: Int
    }

    /// The plugins `claude` failed to load.
    private var failing: Set<PluginID> {
        Set(catalog.snapshot?.problems.compactMap { if case let .loadFailed(id, _) = $0 { id } else { nil } } ?? [])
    }

    var body: some View {
        NavigationSplitView {
            PluginSidebar(snapshot: catalog.snapshot, project: project, selection: $selection) {
                isChoosingFolder = true
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 220)
        } content: {
            PluginEntryList(sections: catalog.entries(in: selection ?? .installed, matching: query),
                       emptyTitle: selection == .installed || selection == nil ? "Nessun plugin installato" : "Nessun plugin",
                       isLoading: catalog.snapshot == nil, isSearching: !query.isEmpty,
                       isListingUnavailable: catalog.isListingUnavailable, failing: failing, marketplaces: catalog.snapshot?.marketplaces ?? [],
                       officialCache: catalog.officialCache, selection: $plugin) { entry in
                installing = entry
            } retry: {
                attempt += 1
            }
            .navigationSplitViewColumnWidth(min: 300, ideal: 380)
        } detail: {
            if let snapshot = catalog.snapshot, let entry = snapshot.plugins.first(where: { $0.id == plugin }) {
                PluginDetail(entry: entry, problems: snapshot.problems.filter { $0.plugin == entry.id },
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
        .onChange(of: catalog.snapshot == nil) { _, isReading in
            if !isReading, selection == nil, let snapshot = catalog.snapshot {
                selection = .initialSelection(in: snapshot)
            }
        }
        .sheet(item: $installing) { entry in
            InstallSheet(entry: entry, marketplace: catalog.snapshot?.marketplace(named: entry.id.marketplace),
                         officialCache: catalog.officialCache, hasProject: project != nil, catalog: catalog)
        }
        .sheet(item: $uninstalling) { entry in
            UninstallSheet(entry: entry, catalog: catalog)
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
}

#Preview {
    PluginsWindow(store: nil)
}
