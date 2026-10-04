import RemoteKit
import SwiftUI

/// The Sessioni tab: the Battito of each Mac, then the Sessioni grouped by Progetto (spec 21).
struct SessionsView: View {
    let model: RemoteModel

    var body: some View {
        List {
            Section {
                ForEach(model.macs) { mac in
                    HeartbeatRow(macName: mac.name, heartbeat: model.snapshots[mac.id]?.heartbeat)
                }
            }
            ForEach(groups) { group in
                Section {
                    ForEach(group.cards) { card in
                        NavigationLink(value: card.id) {
                            SessionRow(card: card)
                        }
                    }
                } header: {
                    Text(verbatim: group.title)
                }
            }
        }
        .overlay {
            if groups.isEmpty {
                ContentUnavailableView("Nessuna Sessione", systemImage: "rectangle.stack",
                                       description: Text("Le Sessioni aperte sul Mac compaiono qui. Quelle dei Progetti solo Mac restano sul Mac."))
            }
        }
        .navigationTitle("Sessioni")
        .navigationDestination(for: UUID.self) { id in
            SessionDetailView(id: id, model: model)
        }
        .refreshable { await model.refresh() }
    }

    /// The Progetti of every Mac, with the Mac's name when more than one is paired.
    private var groups: [ProjectGroup] {
        model.macs.flatMap { mac in
            SessionCard.groupedByProject(model.snapshots[mac.id]?.cards ?? []).map { project, cards in
                ProjectGroup(id: "\(mac.id)/\(project)",
                             title: model.macs.count > 1 ? "\(project) · \(mac.name)" : project,
                             cards: cards)
            }
        }
    }
}

/// The Sessioni of one Progetto on one Mac.
private struct ProjectGroup: Identifiable {
    let id: String
    let title: String
    let cards: [SessionCard]
}

/// A Sessione in the list: the dot of its Attività, its title, "Attività · Fase · N file".
private struct SessionRow: View {
    let card: SessionCard

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            ActivityDot(activity: card.activity)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: card.title)
                    .lineLimit(2)
                Text(verbatim: card.statusLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: card.title))
        .accessibilityValue(Text(verbatim: card.statusLine))
    }
}
