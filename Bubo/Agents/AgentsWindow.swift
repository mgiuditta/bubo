import CoreServices
import os
import SwiftUI

/// The Agenti window, from the Finestra menu: the subagents of the chosen Progetto, with where each comes from, the
/// name conflicts and who wins them, "Apri nell'editor" and Nuovo agente (spec 19).
///
/// The list follows the disk through FSEvents, with no restart. Bubo never writes in an `agents/` folder but for
/// Nuovo agente, after a click.
struct AgentsWindow: View {
    /// The id of the window's scene.
    static let windowID = "agenti"

    /// The Sessioni, for their Progetti and the bridge to `claude`; `nil` when they are unavailable.
    let store: SessionStore?
    /// The user's `~/.claude` folder.
    var user = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude", directoryHint: .isDirectory)
    @AppStorage(EditorLauncher.defaultsKey) private var chosenEditor = ""
    @State private var editor: Editor?
    @State private var project: URL?
    @State private var attempt = 0
    @State private var catalog: AgentCatalog?
    @State private var folders: [AgentFolder] = []
    @State private var files: [AgentFile] = []
    @State private var configuration: ClaudeConfiguration?
    @State private var configurationFailed = false
    /// The `agents/` folders that existed when the Progetto was chosen, or appeared later.
    @State private var knownFolders: Set<URL>?
    /// The `agents/` folders that appeared while the window was open.
    @State private var newFolders: [URL] = []
    @State private var isChoosingFolder = false
    @State private var isCreating = false

    /// What the list is read for: the Progetto, and Riprova.
    private struct LoadKey: Equatable {
        var project: URL?
        var attempt: Int
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            header
            notices
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(Spacing.medium)
        .frame(minWidth: 560, idealWidth: 680, minHeight: 420, idealHeight: 620)
        .font(Typography.body(size: 13))
        .foregroundStyle(Palette.textPrimary)
        // The Notte direction's graphite, under the title bar too, like the Galassia and the Visore (ADR 0004).
        .containerBackground(Palette.ink, for: .window)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .preferredColorScheme(.dark)
        .onAppear { project = project ?? store?.projects.first }
        .task(id: chosenEditor) { editor = EditorLauncher.preferred(chosen: chosenEditor) }
        .task(id: LoadKey(project: project, attempt: attempt)) { await follow() }
        .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
            if case let .success(folder) = result { project = folder }
        }
        .sheet(isPresented: $isCreating) {
            if let project {
                NewAgentSheet(project: project, user: user, files: files, open: openNewAgent)
            }
        }
        // Last, so the sheet gets it too: selection is lightness, not the system blue (design system).
        .tint(Palette.accent)
    }

    private var header: some View {
        HStack {
            Text("Progetto")
                .foregroundStyle(Palette.textSecondary)
            Text(verbatim: project?.lastPathComponent ?? "")
                .font(Typography.body(size: 13, weight: .semibold))
                .help(project?.path ?? "")
            Button(project == nil ? "Scegli cartella…" : "Cambia…") { isChoosingFolder = true }
            Spacer()
            Button("Nuovo agente…", systemImage: "plus") { isCreating = true }
                .disabled(project == nil || catalog == nil)
        }
    }

    @ViewBuilder
    private var notices: some View {
        if configurationFailed {
            HStack(alignment: .firstTextBaseline) {
                AgentNotice("Non riesco a chiedere a claude quali agenti carica: mostro solo i file.", kind: .error)
                Button("Riprova") { attempt += 1 }
            }
        }
        if let configuration, !configuration.loadsProject {
            Label("Progetto non fidato: claude non carica i suoi agenti.", systemImage: "lock")
                .foregroundStyle(Palette.textSecondary)
        }
        if let catalog, catalog.exceedsDescriptionBudget {
            AgentNotice("""
                Le descrizioni degli agenti sono circa \(catalog.descriptionTokens.formatted()) token: oltre \
                \(AgentCatalog.descriptionTokenBudget.formatted()) claude avvisa all'avvio. Accorciale o togli gli \
                agenti che non usi.
                """, kind: .warning)
        }
        if !newFolders.isEmpty, store?.sessions.contains(where: { $0.project == project && $0.isRunning }) == true {
            ForEach(newFolders, id: \.self) { folder in
                AgentNotice("La cartella \(folder.path) è nuova: le Sessioni al lavoro adesso la vedranno dal prossimo turno.",
                            kind: .information)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if project == nil {
            ContentUnavailableView("Scegli la cartella di un Progetto", systemImage: "folder",
                                   description: Text("Mostro gli agenti del Progetto, i tuoi e quelli dei plugin."))
        } else if let catalog {
            if catalog.entries.isEmpty {
                ContentUnavailableView("Nessun agente", systemImage: "person.2",
                                       description: Text("Crea il primo con Nuovo agente."))
            } else {
                List {
                    ForEach(AgentSection.allCases) { section in
                        let entries = catalog.entries.filter { AgentSection(of: $0) == section }
                        if !entries.isEmpty {
                            Section {
                                ForEach(entries) { entry in
                                    AgentRow(entry: entry, isLoadedKnown: configuration != nil, editor: editor,
                                             project: project)
                                }
                            } header: {
                                Text("\(Text(section.title)) · \(entries.count)")
                                    .font(Typography.mono(size: 10, weight: .medium))
                                    .textCase(.uppercase)
                                    .foregroundStyle(Palette.textSecondary)
                            }
                            .listRowSeparatorTint(Palette.line)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        } else {
            LoadingLabel("Leggo gli agenti…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Reading

    /// Reads the agents of the Progetto, then reads them again at each change of an `agents/` folder, until the
    /// Progetto changes or the window closes.
    private func follow() async {
        catalog = nil
        configuration = nil
        configurationFailed = false
        knownFolders = nil
        newFolders = []
        guard let project else { return }
        await reload(project)
        // The repo's root, above the Progetto when it is nested, and `~/.claude`, where the plugins usually are too.
        let root = folders.last { $0.source == .project }.map { $0.url.deletingLastPathComponent().deletingLastPathComponent() }
            ?? project
        let (changes, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        let watchers = [root, user].map { folder in
            Task(priority: .utility) {
                for await batch in FileEvents.batches(under: folder.path, since: FSEventStreamEventId(kFSEventStreamEventIdSinceNow))
                    where batch.needsRescan || batch.paths.contains(where: Self.isInAgentsFolder) {
                    continuation.yield()
                }
            }
        }
        defer {
            watchers.forEach { $0.cancel() }
            continuation.finish()
        }
        for await _ in changes {
            await reload(project)
        }
    }

    /// Whether `path` is an `agents/` folder or inside one.
    nonisolated private static func isInAgentsFolder(_ path: String) -> Bool {
        path.split(separator: "/").contains("agents")
    }

    /// Asks `claude` which agents it loads in `project`, then reads the files of the folders.
    private func reload(_ project: URL) async {
        if let store {
            do {
                configuration = try await store.configuration(of: project)
                configurationFailed = false
            } catch is CancellationError {
                return
            } catch {
                Logger.agent.error("Agents not listed: \(String(describing: error), privacy: .private)")
                configurationFailed = true
            }
        } else {
            configurationFailed = true
        }
        let folders = AgentCatalog.folders(project: project, user: user, plugins: configuration?.plugins ?? [])
        let files = await AgentCatalog.files(in: folders)
        let existing = await AgentCatalog.existing(folders)
        guard !Task.isCancelled else { return }
        if let knownFolders {
            newFolders += existing.subtracting(knownFolders).sorted { $0.path < $1.path }
        }
        knownFolders = (knownFolders ?? []).union(existing)
        self.folders = folders
        self.files = files
        catalog = AgentCatalog(folders: folders, files: files, loaded: configuration?.agents,
                               loadsProject: configuration?.loadsProject ?? true)
    }

    /// Opens the file Nuovo agente wrote at its empty body, in the editor, or in the Finder when there is none.
    private func openNewAgent(_ file: URL) {
        if let editor {
            EditorLauncher.open(SourceLocation(file: file, line: AgentFileWriter.bodyLine),
                                in: AgentRow.window(for: file, in: project), with: editor)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([file])
        }
    }
}

/// The sections of the Agenti window, by where the agent `claude` uses comes from.
private enum AgentSection: CaseIterable, Identifiable {
    case project, user, plugin, builtIn

    init(of entry: AgentCatalog.Entry) {
        switch entry.source {
        case .project: self = .project
        case .user: self = .user
        case .plugin: self = .plugin
        case nil: self = .builtIn
        }
    }

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .project: "Progetto"
        case .user: "Utente"
        case .plugin: "Plugin"
        case .builtIn: "Incorporati"
        }
    }
}

#Preview {
    AgentsWindow(store: nil)
}
