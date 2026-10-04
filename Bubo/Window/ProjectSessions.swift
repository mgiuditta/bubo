import SwiftUI

/// The Sessioni of a Progetto, newest first; a click opens one on the right.
struct ProjectSessions: View {
    let project: URL
    let store: SessionStore
    @Binding var selection: SidebarSelection
    @Environment(HUDPresenter.self) private var hud

    private var items: [ConversationItem] {
        ConversationList.items(questions: [], sessions: store.sessions.filter { $0.project == project }, cli: [],
                               includingCLI: false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack {
                Text(project.lastPathComponent)
                    .buboTitleStyle()
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Nuova Sessione", systemImage: "plus") {
                    var draft = SessionDraft()
                    draft.project = project
                    hud.createSession(from: draft)
                }
            }
            if items.isEmpty {
                ContentUnavailableView("Nessuna Sessione", systemImage: "folder",
                                       description: Text("Scrivi nel Cervello «entra in \(project.lastPathComponent) e…» oppure crea una Sessione."))
            } else {
                List(items) { item in
                    Button { selection = .conversation(item.id) } label: { ConversationRow(item: item) }
                        .buttonStyle(.plain)
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: Spacing.readingWidth, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity)
        .padding(Spacing.l)
    }
}
