import SwiftUI

/// The avviso nel Progetto about its Risorse di squadra (ADR 0009): how many `allow` of `.bubo/regole.json` are still
/// to look at, or in red that the file cannot be read, so nobody believes a `deny` applies; Guarda… opens the foglio.
///
/// Nothing shows when there is nothing to decide.
struct TeamResourcesNotice: View {
    @State private var reader: TeamResourceReader
    @State private var isReviewing = false

    /// Creates the notice of the Progetto `project`.
    init(project: URL) {
        _reader = State(initialValue: TeamResourceReader(project: project))
    }

    private var name: String { reader.root.lastPathComponent }

    var body: some View {
        content
            .task(id: reader.root) { await reader.watch() }
            .sheet(isPresented: $isReviewing) { TeamResourcesSheet(reader: reader) }
    }

    @ViewBuilder
    private var content: some View {
        if reader.state == .unreadable {
            ErrorNotice("Le regole di squadra non si leggono",
                        remedy: "Correggi .bubo/regole.json in \(name): finché non si legge, non vale nessuna regola di squadra, nemmeno i deny.",
                        actionTitle: "Guarda…") { isReviewing = true }
                .padding(.top, Spacing.xSmall)
        } else if reader.pendingCount > 0 {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
                Label {
                    VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                        Text("Nel repo ci sono \(reader.pendingCount) Risorse di squadra da guardare")
                        Text(verbatim: name)
                            .foregroundStyle(Palette.textSecondary)
                    }
                } icon: {
                    Image(systemName: "person.2")
                        .accessibilityHidden(true)
                }
                .font(Typography.body(size: 13))
                Spacer(minLength: Spacing.small)
                Button("Guarda…") { isReviewing = true }
            }
            .padding(Spacing.small)
            .background(Palette.surface, in: .rect(cornerRadius: CornerRadius.large))
            .padding(.top, Spacing.xSmall)
        } else {
            // Keeps the view in the hierarchy, so the watch goes on while there is nothing to show.
            Color.clear.frame(height: 0)
        }
    }
}
