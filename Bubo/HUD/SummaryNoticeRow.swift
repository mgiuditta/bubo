import SwiftUI
import UniformTypeIdentifiers

/// What the card of a Sessione says about its Riassunto di Sessione: saved, queued, or where to save it.
struct SummaryNoticeRow: View {
    let notice: SessionSummarizer.Notice
    let summarizer: SessionSummarizer
    @State private var isChoosingFolder = false

    var body: some View {
        Group {
            switch notice {
            case .needsFolder:
                VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                    Text("Dove salvo i riassunti delle Sessioni?")
                    HStack {
                        Button("Scegli la cartella…") { isChoosingFolder = true }
                        Button("Non salvarli", action: summarizer.declineSummaries)
                    }
                    .controlSize(.small)
                }
                .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
                    guard case let .success(folder) = result else { return }
                    Task { await summarizer.choose(folder) }
                }
            case .waitingForNetwork:
                Text("Riassunto in coda: lo scrivo quando torna la rete.")
            case .secondBrainUnreachable:
                Text("Riassunto in coda: il Secondo cervello non è raggiungibile.")
            case .saved:
                Text("Riassunto salvato nel Secondo cervello")
            }
        }
        .font(Typography.body(size: 12))
        .foregroundStyle(Palette.textSecondary)
    }
}
