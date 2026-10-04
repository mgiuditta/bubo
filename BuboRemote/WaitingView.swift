import RemoteKit
import SwiftUI

/// The Attende te tab: the Battito of each Mac, then the Richieste from the oldest (spec 21).
///
/// Levels 1–3 are decided on their tile; levels 4–5 only on the full-screen page. With nothing to decide, the Novità:
/// the latest message of each Sessione.
struct WaitingView: View {
    let model: RemoteModel
    @State private var error: DecisionError?

    var body: some View {
        let waiting = model.waitingRequests
        List {
            Section {
                ForEach(model.macs) { mac in
                    HeartbeatRow(macName: mac.name, heartbeat: model.snapshots[mac.id]?.heartbeat)
                }
            }
            if !waiting.isEmpty {
                Section {
                    ForEach(waiting) { waiting in
                        RequestTile(waiting: waiting, showsMac: model.macs.count > 1, decide: decide) {
                            model.focusedRequest = waiting.id
                        }
                    }
                } header: {
                    Text("\(waiting.count) in attesa")
                } footer: {
                    Text("Sempre in questo Progetto: solo dal Mac.")
                }
            } else {
                Section {
                    ContentUnavailableView {
                        Label("Niente da decidere", systemImage: "checkmark.circle")
                    } description: {
                        Text("\(workingCount) Sessioni lavorano")
                    }
                }
                let news = model.news
                if !news.isEmpty {
                    Section("Novità") {
                        ForEach(news) { card in
                            NavigationLink(value: card.id) {
                                NewsRow(card: card)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Attende te")
        .navigationDestination(for: UUID.self) { id in
            SessionDetailView(id: id, model: model)
        }
        .refreshable { await model.refresh() }
        .fullScreenCover(item: focused) { waiting in
            RequestReviewView(waiting: waiting, decide: decide) { model.focusedRequest = nil }
                .alert(isPresented: isShowingError, error: error) {}
        }
        .alert(isPresented: isShowingError, error: error) {}
    }

    /// Whether the reason of the last failed decision shows, above the full-screen page when it is open.
    private var isShowingError: Binding<Bool> {
        Binding { error != nil } set: { if !$0 { error = nil } }
    }

    /// The Sessioni in Lavora on every Mac.
    private var workingCount: Int {
        model.snapshots.values.reduce(0) { $0 + $1.cards.count { $0.activity == .lavora } }
    }

    /// The Richiesta a notification or a tile opened, while it still waits.
    private var focused: Binding<WaitingRequest?> {
        Binding {
            model.waitingRequests.first { $0.id == model.focusedRequest }
        } set: {
            model.focusedRequest = $0?.id
        }
    }

    private func decide(_ waiting: WaitingRequest, _ answer: Verdict.Answer) async {
        do {
            try await model.answer(waiting.id, of: waiting.macID, with: answer, expiresAt: waiting.request.expiresAt)
        } catch {
            self.error = error
        }
    }
}

extension DecisionError: LocalizedError {
    var errorDescription: String? { String(localized: message) }
}

/// A Sessione in the Novità: its title, and its latest message below.
private struct NewsRow: View {
    let card: SessionCard

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: card.title)
                .lineLimit(1)
            Text(verbatim: card.excerpt ?? "")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
    }
}
