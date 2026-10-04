import SwiftUI

/// The sidebar of the window: Cervello, Neuroni and Riunioni; the Domande and the Sessioni by day; the Progetti and
/// Lavoro; Impostazioni at the bottom (ADR 0013).
struct MainSidebar: View {
    @Binding var selection: SidebarSelection
    let questions: QuestionModel
    let sessions: SessionStore?
    /// Whether the conversations of the command line show among the others.
    @AppStorage("mostraRigaDiComando") private var includesCLI = false
    @State private var history: [CLIConversation] = []
    @Environment(\.openSettings) private var openSettings
    @Environment(HUDPresenter.self) private var hud
    @State private var isChoosingProject = false
    @AppStorage(ReleaseArea.hidesUnreleasedKey) private var hidesUnreleased = false

    var body: some View {
        List(selection: $selection) {
            Section {
                Label("Cervello", systemImage: "brain").tag(SidebarSelection.brain)
                // Not a dead end at the top of the navigation: off where the area is not released (1.1).
                if ReleaseArea.neurons.isAvailable(hidesUnreleased: hidesUnreleased) {
                    Label("Neuroni", systemImage: "point.3.connected.trianglepath.dotted").tag(SidebarSelection.neurons)
                }
                Label("Riunioni", systemImage: "waveform").tag(SidebarSelection.meetings)
            }
            ForEach(groups, id: \.group) { group in
                Section(String(localized: group.group.title)) {
                    ForEach(group.items) { item in
                        ConversationRow(item: item).tag(SidebarSelection.conversation(item.id))
                    }
                }
            }
            // Always there, even before the first Sessione: it is where a Progetto is added.
            if let sessions {
                Section("Progetti") {
                    ForEach(sessions.projects, id: \.self) { project in
                        Label(project.lastPathComponent, systemImage: "folder").tag(SidebarSelection.project(project))
                    }
                    if !sessions.projects.isEmpty {
                        Label("Lavoro", systemImage: "rectangle.split.3x1").tag(SidebarSelection.work)
                    }
                    Button("Aggiungi Progetto…", systemImage: "plus") { isChoosingProject = true }
                        .buttonStyle(.plain)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
        }
        .listStyle(.sidebar)
        .environment(\.defaultMinListRowHeight, Spacing.sidebarRowMinHeight)
        .safeAreaInset(edge: .bottom, alignment: .leading) {
            GlassCapsuleButton("Impostazioni", systemImage: "gearshape") { openSettings() }
                .padding(Spacing.m)
        }
        .toolbar {
            Toggle("Mostra la Cronologia CLI", systemImage: "terminal", isOn: $includesCLI)
                .help(Text("Mostra anche le conversazioni della Cronologia CLI"))
        }
        // A Progetto exists through its Sessioni: the chosen folder opens the new Sessione's sheet on it.
        .fileImporter(isPresented: $isChoosingProject, allowedContentTypes: [.folder]) { result in
            guard case let .success(folder) = result else { return }
            var draft = SessionDraft()
            draft.project = folder
            hud.createSession(from: draft)
        }
        .task(id: includesCLI) {
            guard includesCLI, let sessions else { return }
            history = (try? await sessions.history(isComplete: false)) ?? []
        }
    }

    private var groups: [(group: DayGroup, items: [ConversationItem])] {
        let items = ConversationList.items(questions: questions.archive?.questions ?? [],
                                           sessions: sessions?.sessions ?? [], cli: history,
                                           includingCLI: includesCLI)
        return ConversationList.groups(of: items, now: .now, calendar: .current)
    }
}
