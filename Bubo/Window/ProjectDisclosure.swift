import SwiftUI

/// A Progetto in the sidebar that opens on its latest Sessioni, closed by default so that many Progetti stay short.
struct ProjectDisclosure: View {
    let project: URL
    let sessions: SessionStore
    let selection: SidebarSelection
    /// Whether the Progetto is open, remembered per folder across launches.
    @AppStorage private var isExpanded: Bool

    /// The Sessioni shown under the Progetto; the others are one click away in the Progetto itself.
    private static let shownSessions = 5

    init(project: URL, sessions: SessionStore, selection: SidebarSelection) {
        self.project = project
        self.sessions = sessions
        self.selection = selection
        _isExpanded = AppStorage(wrappedValue: false, "progettoAperto.\(project.path(percentEncoded: false))")
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(items.prefix(Self.shownSessions)) { item in
                Text(item.title)
                    .font(.buboInterface)
                    .lineLimit(1)
                    .selectableRow(SidebarSelection.conversation(item.id), selection: selection)
            }
            if items.count > Self.shownSessions {
                Text("Tutte le Sessioni (\(items.count))")
                    .font(.buboInterface)
                    .foregroundStyle(Palette.textSecondary)
                    .selectableRow(SidebarSelection.project(project), selection: selection)
            }
        } label: {
            Label(project.lastPathComponent, systemImage: "folder")
                .selectableRow(SidebarSelection.project(project), selection: selection)
        }
    }

    /// The Progetto's Sessioni, newest first.
    private var items: [ConversationItem] {
        ConversationList.items(questions: [], sessions: sessions.sessions.filter { $0.project == project }, cli: [],
                               includingCLI: false)
    }
}
