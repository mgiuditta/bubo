import RemoteKit
import SwiftUI

/// A Sessione on the iPhone: Progetto, title, Attività, Fase, diff and the latest message (spec 21).
///
/// Follows the card as it changes on the Mac; the Richieste, Rispondi and Ferma come with their own steps.
struct SessionDetailView: View {
    /// The Sessione's identifier on the Mac.
    let id: UUID
    let model: RemoteModel

    var body: some View {
        if let card = model.snapshots.values.lazy.flatMap(\.cards).first(where: { $0.id == id }) {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: card.project)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(verbatim: card.title)
                            .font(.title3.bold())
                            .accessibilityAddTraits(.isHeader)
                    }
                    LabeledContent("Attività") {
                        HStack(spacing: 6) {
                            ActivityDot(activity: card.activity)
                                .accessibilityHidden(true)
                            Text(card.activity.title)
                        }
                    }
                    LabeledContent("Fase") { Text(card.phase.title) }
                }
                if let diff = card.diff {
                    Section("Modifiche") {
                        LabeledContent("File", value: diff.files, format: .number)
                        LabeledContent("Righe aggiunte", value: diff.addedLines, format: .number)
                        LabeledContent("Righe tolte", value: diff.removedLines, format: .number)
                    }
                }
                if let excerpt = card.excerpt {
                    Section("Ultimi messaggi") {
                        Text(verbatim: excerpt)
                    }
                }
            }
            .navigationTitle(card.title)
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("Sessione non più sull'iPhone", systemImage: "rectangle.stack",
                                   description: Text("È stata archiviata o il suo Progetto è solo Mac."))
        }
    }
}
