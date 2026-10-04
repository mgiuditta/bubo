import SwiftUI

/// The Aggiorna sheet, only when the new version brings code on the Mac: only the new components, or "componenti
/// sconosciuti" when nothing says what it brings; for a `command` source, the command with its fingerprint and the box
/// that unlocks Aggiorna (spec 20, Fogli).
struct UpdateSheet: View {
    let entry: PluginEntry
    let update: PluginUpdate
    /// The components of the new version that run code on the Mac and the installed one lacks; `nil` when unknown.
    let newCode: [PluginComponent]?
    let catalog: PluginCatalog
    /// What the detail says after it, when `claude` left the version as it was.
    @Binding var notice: Text?
    @Environment(\.dismiss) private var dismiss
    /// The command the CLI showed and refused to run without confirmation.
    @State private var shown: PluginShownCommand?
    @State private var isAccepted = false
    @State private var failure: Text?
    @State private var updating: Task<Void, Never>?

    /// Creates the sheet for `update` of `entry`, with the command the CLI already showed when `shown` is set.
    init(entry: PluginEntry, update: PluginUpdate, newCode: [PluginComponent]?, shown: PluginShownCommand? = nil,
         catalog: PluginCatalog, notice: Binding<Text?>) {
        self.entry = entry
        self.update = update
        self.newCode = newCode
        self.catalog = catalog
        _notice = notice
        _shown = State(initialValue: shown)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            Text("Aggiorna \(entry.displayName)")
                .font(Typography.body(size: 15, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.medium) {
                    newCodeSection
                    if let shown { commandSection(shown) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 280)
            if let failure {
                failure
                    .font(Typography.body(size: 12))
                    .foregroundStyle(Palette.danger)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if updating != nil {
                    LoadingLabel("Aggiorno…")
                }
                Spacer()
                Button("Annulla", role: .cancel) {
                    updating?.cancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Aggiorna", action: apply)
                    .keyboardShortcut(.defaultAction)
                    .disabled(updating != nil || shown != nil && !isAccepted)
            }
        }
        .padding(Spacing.large)
        .frame(width: 460)
    }

    @ViewBuilder
    private var newCodeSection: some View {
        if let newCode {
            if !newCode.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.small) {
                    Text("La nuova versione porta codice che gira sul Mac, fuori dalla sandbox.")
                        .font(Typography.body(size: 12))
                        .foregroundStyle(Palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    PluginInventoryList(inventory: PluginInventory(components: newCode), isInstalled: false,
                                        title: Text("Componenti nuovi"))
                }
            }
        } else {
            Label("Componenti sconosciuti: può eseguire codice sul Mac", systemImage: "questionmark.circle")
                .font(Typography.body(size: 12))
                .foregroundStyle(Palette.textSecondary)
                .padding(Spacing.small)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.surface, in: .rect(cornerRadius: 8))
        }
    }

    private func commandSection(_ shown: PluginShownCommand) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Text("Per aggiornarlo, claude esegue questo comando sul Mac:")
                .font(Typography.body(size: 12))
                .foregroundStyle(Palette.textPrimary)
            Text(verbatim: shown.command)
                .font(Typography.mono(size: 12))
                .foregroundStyle(Palette.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Text("Impronta sha256")
                .font(Typography.body(size: 11))
                .foregroundStyle(Palette.textSecondary)
            Text(verbatim: shown.sha256)
                .font(Typography.mono(size: 10))
                .foregroundStyle(Palette.textSecondary)
                .textSelection(.enabled)
            Toggle("Ho letto il comando e mi fido", isOn: $isAccepted)
                .toggleStyle(.checkbox)
        }
        .padding(Spacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: .rect(cornerRadius: 8))
    }

    private func apply() {
        failure = nil
        let accepting = isAccepted ? shown : nil
        updating = Task {
            defer { updating = nil }
            do {
                switch try await catalog.apply(update, accepting: accepting) {
                case .updated:
                    dismiss()
                case .unchanged:
                    notice = Text(PluginUpdateOutcome.unchangedMessage)
                    dismiss()
                case let .needsConfirmation(command):
                    // A command changed since it was read needs a new tick.
                    if command != shown || !isAccepted {
                        shown = command
                        isAccepted = false
                    } else {
                        failure = Text("claude non ha accettato il comando confermato.")
                    }
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
