import SwiftUI

/// The update box of the detail: the version the Marketplace offers and Aggiorna, in one click when the new version
/// brings no new code on the Mac, otherwise through the Aggiorna sheet (spec 20, Dettaglio).
struct PluginUpdateBox: View {
    let entry: PluginEntry
    let update: PluginUpdate
    let marketplace: Marketplace?
    let officialCache: OfficialCatalogCache?
    let catalog: PluginCatalog
    /// What the detail says after it, when `claude` left the version as it was.
    @Binding var notice: Text?
    @State private var isWorking = false
    @State private var failure: Text?
    @State private var confirmation: Confirmation?

    /// What the Aggiorna sheet asks to confirm.
    private struct Confirmation: Identifiable {
        let id = UUID()
        let newCode: [PluginComponent]?
        var shown: PluginShownCommand?
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Label {
                title
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(Palette.textSecondary)
                    .accessibilityHidden(true)
            }
            HStack(spacing: Spacing.small) {
                Button("Aggiorna", action: run)
                    .buttonStyle(.borderedProminent)
                    .disabled(isWorking || catalog.pending.contains(entry.id))
                if isWorking {
                    LoadingLabel("Aspetto claude…")
                }
            }
            if let failure {
                failure
                    .foregroundStyle(Palette.danger)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(Typography.body(size: 12))
        .padding(Spacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: .rect(cornerRadius: 8))
        .sheet(item: $confirmation) { confirmation in
            UpdateSheet(entry: entry, update: update, newCode: confirmation.newCode, shown: confirmation.shown,
                        catalog: catalog, notice: $notice)
        }
    }

    private var title: Text {
        switch update.certainty {
        case .certain: Text("Aggiornamento disponibile: versione \(update.displayVersion)")
        case .possible: Text("Forse c'è un aggiornamento: il repository è passato a \(update.displayVersion)")
        }
    }

    /// Compares the components of the new version with the installed ones: no new code, one click; otherwise the
    /// sheet.
    private func run() {
        failure = nil
        notice = nil
        isWorking = true
        Task {
            defer { isWorking = false }
            let installed = await PluginInventory.inventory(of: entry, marketplace: marketplace, officialCache: officialCache)
            let latest = await PluginInventory.latestInventory(of: entry, marketplace: marketplace, officialCache: officialCache)
            let newCode = PluginUpdateChecker.newExecutables(installed: installed, latest: latest)
            guard newCode?.isEmpty == true else {
                confirmation = Confirmation(newCode: newCode)
                return
            }
            do {
                switch try await catalog.apply(update) {
                case .updated:
                    break
                case .unchanged:
                    notice = Text(PluginUpdateOutcome.unchangedMessage)
                case let .needsConfirmation(shown):
                    confirmation = Confirmation(newCode: [], shown: shown)
                case let .failed(result):
                    failure = Text(marketplaceFailure: result)
                }
            } catch is CancellationError {
                return
            } catch {
                failure = Text(marketplaceError: error)
            }
        }
    }
}
