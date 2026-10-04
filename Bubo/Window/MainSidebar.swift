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

    var body: some View {
        List(selection: $selection) {
            Section {
                Label("Cervello", systemImage: "brain").tag(SidebarSelection.brain)
                Label("Neuroni", systemImage: "point.3.connected.trianglepath.dotted").tag(SidebarSelection.neurons)
                Label("Riunioni", systemImage: "waveform").tag(SidebarSelection.meetings)
            }
            ForEach(groups, id: \.group) { group in
                Section(String(localized: group.group.title)) {
                    ForEach(group.items) { item in
                        ConversationRow(item: item).tag(SidebarSelection.conversation(item.id))
                    }
                }
            }
            if let sessions, !sessions.projects.isEmpty {
                Section("Progetti") {
                    ForEach(sessions.projects, id: \.self) { project in
                        Label(project.lastPathComponent, systemImage: "folder").tag(SidebarSelection.project(project))
                    }
                    Label("Lavoro", systemImage: "rectangle.split.3x1").tag(SidebarSelection.work)
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
            Toggle("Mostra anche la riga di comando", systemImage: "terminal", isOn: $includesCLI)
                .help(Text("Mostra anche le conversazioni avviate dalla riga di comando"))
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
