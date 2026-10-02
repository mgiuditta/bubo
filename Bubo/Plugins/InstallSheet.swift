import SwiftUI

/// The Installa sheet: scope, what the plugin installs or "componenti sconosciuti", and for a `command` source the
/// command with its fingerprint and the box that unlocks Installa (spec 20, Fogli).
struct InstallSheet: View {
    let entry: PluginEntry
    let marketplace: Marketplace?
    let officialCache: OfficialCatalogCache?
    /// Whether the window has a Progetto: without one, only Per me.
    let hasProject: Bool
    let catalog: PluginCatalog
    @Environment(\.dismiss) private var dismiss
    @State private var scope = PluginScope.user
    @State private var inventory: PluginInventory?
    @State private var hasReadInventory = false
    @State private var confirmation = InstallConfirmation()
    @State private var failure: Text?
    @State private var installing: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            Text("Installa \(entry.displayName)")
                .font(Typography.body(size: 15, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            scopePicker
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.medium) {
                    if hasReadInventory { inventorySection }
                    commandSection
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
                if installing != nil {
                    LoadingLabel("Installo…")
                }
                Spacer()
                Button("Annulla", role: .cancel) {
                    installing?.cancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Installa", action: install)
                    .keyboardShortcut(.defaultAction)
                    .disabled(installing != nil || !confirmation.allowsInstall)
            }
        }
        .padding(Spacing.large)
        .frame(width: 460)
        .task {
            inventory = await PluginInventory.inventory(of: entry, marketplace: marketplace, officialCache: officialCache)
            hasReadInventory = true
        }
    }

    private var scopePicker: some View {
        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
            Picker("Per chi", selection: $scope) {
                Text("Per me").tag(PluginScope.user)
                Text("Per questo Progetto").tag(PluginScope.project)
                    .selectionDisabled(!hasProject)
                Text("Solo io qui").tag(PluginScope.local)
                    .selectionDisabled(!hasProject)
            }
            .pickerStyle(.radioGroup)
            if scope == .project {
                Text("Gli altri lo installano dal proprio Mac.")
                    .font(Typography.body(size: 11))
                    .foregroundStyle(Palette.textSecondary)
            }
        }
    }

    @ViewBuilder
    private var inventorySection: some View {
        if let inventory {
            PluginInventoryList(inventory: inventory, isInstalled: false)
        } else {
            Label("Componenti sconosciuti: può eseguire codice sul Mac", systemImage: "questionmark.circle")
                .font(Typography.body(size: 12))
                .foregroundStyle(Palette.textSecondary)
                .padding(Spacing.small)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.surface, in: .rect(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private var commandSection: some View {
        if let shown = confirmation.shownCommand {
            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                Text("Per installarlo, claude esegue questo comando sul Mac:")
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
                Toggle("Ho letto il comando e mi fido", isOn: $confirmation.isAccepted)
                    .toggleStyle(.checkbox)
            }
            .padding(Spacing.small)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: .rect(cornerRadius: 8))
        } else if case let .command(command) = entry.source {
            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                Text("Si installa eseguendo un comando sul Mac:")
                    .font(Typography.body(size: 12))
                    .foregroundStyle(Palette.textPrimary)
                Text(verbatim: command)
                    .font(Typography.mono(size: 12))
                    .foregroundStyle(Palette.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Prima di eseguirlo ti mostro il comando come lo vede claude, con la sua impronta.")
                    .font(Typography.body(size: 11))
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func install() {
        let command = confirmation.installCommand(for: entry.id, scope: scope)
        failure = nil
        installing = Task {
            defer { installing = nil }
            do {
                let result = try await catalog.perform(command)
                if result.succeeded {
                    dismiss()
                } else if !confirmation.update(with: result) {
                    failure = Text(verbatim: result.message)
                }
            } catch is CancellationError {
                return
            } catch let error as PluginCLIError {
                failure = Text(error.message)
            } catch {
                failure = Text(verbatim: error.localizedDescription)
            }
        }
    }
}
