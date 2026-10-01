import SwiftUI

/// The Risorse di squadra of a Progetto in its Configurazione di Claude: what `.bubo/regole.json` holds and how much is
/// still to look at, with Guarda… for the foglio.
struct TeamResourcesSection: View {
    @State private var reader: TeamResourceReader
    @State private var isReviewing = false

    /// Creates the section of the Progetto `project`.
    init(project: URL) {
        _reader = State(initialValue: TeamResourceReader(project: project))
    }

    var body: some View {
        Section("Risorse di squadra") {
            switch reader.state {
            case .loading:
                EmptyView()
            case .missing:
                Text("Il repo non ha regole di squadra in .bubo/regole.json.")
                    .foregroundStyle(.secondary)
            case .unreadable:
                Label {
                    Text("Le regole di squadra non si leggono: non vale nessuna, nemmeno i deny.")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Palette.danger)
                        .accessibilityLabel("Errore")
                }
                reviewButton
            case let .rules(rules):
                LabeledContent {
                    reviewButton
                } label: {
                    Text("\(reader.pendingCount) da guardare · \(rules.allow.count - reader.pendingCount) decise · \(rules.deny.count + rules.ask.count) già attive")
                }
            }
        }
        .task(id: reader.root) { await reader.watch() }
        .sheet(isPresented: $isReviewing) { TeamResourcesSheet(reader: reader) }
    }

    private var reviewButton: some View {
        Button("Guarda…") { isReviewing = true }
    }
}
