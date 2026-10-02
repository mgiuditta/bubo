import SwiftUI

/// The Disinstalla sheet: Disattiva is the way to just turn it off, "Tieni i dati del plugin" off by default, and the
/// dependencies nothing needs any more removed in the same confirmation (spec 20, Fogli).
///
/// `claude plugin uninstall --json` does not combine with `--prune`: after the uninstall, `claude plugin prune -y` of
/// the same scope (preflight of #207).
struct UninstallSheet: View {
    let entry: PluginEntry
    let catalog: PluginCatalog
    @Environment(\.dismiss) private var dismiss
    @State private var scope: PluginScope
    @State private var keepsData = false
    @State private var failure: Text?
    @State private var uninstalling: Task<Void, Never>?

    /// Creates the sheet of `entry`, on the first scope it can be uninstalled from.
    init(entry: PluginEntry, catalog: PluginCatalog) {
        self.entry = entry
        self.catalog = catalog
        _scope = State(initialValue: entry.uninstallableScopes.first ?? .user)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            Text("Disinstallare \(entry.displayName)?")
                .font(Typography.body(size: 15, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("Per spegnerlo e basta, usa Disattiva.")
                .font(Typography.body(size: 12))
                .foregroundStyle(Palette.textSecondary)
            if entry.uninstallableScopes.count > 1 {
                Picker("Da dove", selection: $scope) {
                    ForEach(entry.uninstallableScopes, id: \.self) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .pickerStyle(.radioGroup)
            }
            Toggle("Tieni i dati del plugin", isOn: $keepsData)
                .toggleStyle(.checkbox)
            Text("Toglie anche le dipendenze che nessun plugin usa più.")
                .font(Typography.body(size: 11))
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let failure {
                failure
                    .font(Typography.body(size: 12))
                    .foregroundStyle(Palette.danger)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if uninstalling != nil {
                    LoadingLabel("Disinstallo…")
                }
                Spacer()
                // No default action: Invio never uninstalls (spec 20, Accessibilità).
                Button("Annulla", role: .cancel) {
                    uninstalling?.cancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Disinstalla", role: .destructive, action: uninstall)
                    .foregroundStyle(Palette.danger)
                    .disabled(uninstalling != nil)
            }
        }
        .padding(Spacing.large)
        .frame(width: 420)
    }

    private func uninstall() {
        let command = PluginCommand.uninstall(entry.id, scope: scope, keepingData: keepsData)
        let scope = scope
        failure = nil
        uninstalling = Task {
            defer { uninstalling = nil }
            do {
                let result = try await catalog.perform(command)
                guard result.succeeded else {
                    failure = Text(verbatim: result.message)
                    return
                }
                let pruned = try await catalog.perform(.prune(scope: scope))
                if pruned.succeeded {
                    dismiss()
                } else {
                    failure = Text("Disinstallato, ma non sono riuscito a togliere le dipendenze rimaste.")
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
