import SwiftUI

/// The right column of the foglio di Consegna, in this order: Da decidere, Cosa esce, Tolto da Bubo, Conversazione
/// ripulita. "Mostra nella conversazione" scrolls the last one to the secret's message and marks it.
struct DeliveryContents: View {
    let preview: DeliveryBuilder.Preview
    let flow: DeliveryFlow

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.medium) {
                    if !preview.findings.isEmpty { decisions }
                    contents
                    removed
                    Text("Conversazione ripulita")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(preview.lines) { line in
                        DeliveryPreviewLineView(line: line, findings: findingsByID, decisions: decision(for:),
                                                isShown: line.id == flow.shownLine)
                            .id(line.id)
                    }
                }
                .padding(Spacing.medium)
            }
            .onChange(of: flow.shownLine) { _, line in
                guard let line else { return }
                withAnimation(Motion.isReduced ? nil : Motion.standard) { proxy.scrollTo(line, anchor: .center) }
            }
        }
    }

    private var findingsByID: [SecretScanner.Finding.ID: SecretScanner.Finding] {
        Dictionary(preview.findings.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func decision(for id: SecretScanner.Finding.ID) -> DeliveryChoices.Decision? {
        flow.choices.decisions[id]
    }

    private var decisions: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Text("Da decidere (\(flow.choices.undecidedCount))")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text("Lo scanner non trova tutto: guarda anche la conversazione qui sotto.")
                .font(.caption)
                .foregroundStyle(Palette.textSecondary)
            ForEach(preview.findings) { finding in
                SecretDecisionRow(finding: finding, decision: decision(for: finding.id),
                                  isInBranch: preview.findingsInBranch.contains(finding.id),
                                  decide: { flow.decide($0, for: finding) }, show: { flow.show(finding) })
            }
        }
    }

    private var contents: some View {
        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
            Text("Cosa esce")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text("Conversazione: \(preview.cleaned.messageCount) messaggi, con strumenti e risultati")
            Text("Sotto-agenti: \(preview.cleaned.files.subagents.count), ripuliti allo stesso modo")
            if let branch = preview.branch {
                if branch.isEmpty {
                    Text("Ramo \(branch.branch): niente di nuovo rispetto alla base")
                } else if branch.hasUncommittedChanges {
                    Text("Ramo \(branch.branch): \(branch.commitCount) commit, \(branch.changedFiles.count) file, con le modifiche non salvate")
                } else {
                    Text("Ramo \(branch.branch): \(branch.commitCount) commit, \(branch.changedFiles.count) file")
                }
            } else {
                Text("Niente ramo: il Progetto non è un repo")
            }
        }
        .font(.callout)
    }

    private var removed: some View {
        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
            Text("Tolto da Bubo")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text("Email e organizzazione dell'account")
            Text("Percorsi del Mac, diventati \(TranscriptCleaner.projectPlaceholder)")
            Text("Prompt di sistema (prompt_snapshot) e \(preview.cleaned.removed[.metadata] ?? 0) righe di metadati fuori dalla conversazione")
            Text("\(preview.cleaned.removed[.reasoning] ?? 0) blocchi di ragionamento")
        }
        .font(.callout)
    }
}
