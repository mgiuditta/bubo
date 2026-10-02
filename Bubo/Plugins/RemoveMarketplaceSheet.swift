import SwiftUI

/// The confirmation of Rimuovi marketplace: where it is declared, and every plugin `claude` uninstalls with it
/// (spec 20, preflight of #208).
///
/// `claude plugin marketplace remove` without `--scope` takes it from every scope; the plugins go only when the last
/// declaration goes, and then from every scope and Progetto, with their options and data.
struct RemoveMarketplaceSheet: View {
    let marketplace: Marketplace
    /// Every plugin installed from it, in any scope and Progetto.
    let plugins: [PluginID]
    let catalog: PluginCatalog
    @Environment(\.dismiss) private var dismiss
    /// The scope to take it from; `nil` for every scope.
    @State private var scope: PluginScope?
    @State private var failure: Text?
    @State private var removing: Task<Void, Never>?

    /// Creates the confirmation for `marketplace`, from the user's settings when several declare it, so a Progetto
    /// shared in git is never changed by default.
    init(marketplace: Marketplace, plugins: [PluginID], catalog: PluginCatalog) {
        self.marketplace = marketplace
        self.plugins = plugins
        self.catalog = catalog
        let isShared = marketplace.declaredScopes.count > 1
        _scope = State(initialValue: isShared && marketplace.declaredScopes.contains(.user) ? .user : nil)
    }

    /// Whether this removal takes the last declaration, and with it the plugins.
    private var removesPlugins: Bool { marketplace.removalScope(scope) == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            Text("Rimuovere il marketplace \(marketplace.name)?")
                .font(Typography.body(size: 15, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            if marketplace.declaredScopes.count > 1 {
                Picker("Da dove", selection: $scope) {
                    ForEach(marketplace.declaredScopes, id: \.self) { scope in
                        Text(scope.title).tag(Optional(scope))
                    }
                    Text("Ovunque").tag(PluginScope?.none)
                }
                .pickerStyle(.radioGroup)
            }
            if removesPlugins {
                removedPlugins
            } else {
                Text("Resta dichiarato altrove: i suoi plugin restano installati.")
                    .font(Typography.body(size: 12))
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let failure {
                failure
                    .font(Typography.body(size: 12))
                    .foregroundStyle(Palette.danger)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if removing != nil {
                    LoadingLabel("Rimuovo…")
                }
                Spacer()
                // No default action: Invio never removes (spec 20, Accessibilità).
                Button("Annulla", role: .cancel) {
                    removing?.cancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Rimuovi", role: .destructive, action: remove)
                    .foregroundStyle(Palette.danger)
                    .disabled(removing != nil)
            }
        }
        .padding(Spacing.large)
        .frame(width: 440)
    }

    @ViewBuilder
    private var removedPlugins: some View {
        if plugins.isEmpty {
            Text("Nessun plugin installato da questo marketplace.")
                .font(Typography.body(size: 12))
                .foregroundStyle(Palette.textSecondary)
        } else {
            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                Text("Disinstalla anche questi plugin (\(plugins.count)), in ogni Progetto, con le loro opzioni e i loro dati:")
                    .font(Typography.body(size: 12))
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                        ForEach(plugins, id: \.self) { plugin in
                            Text(verbatim: plugin.name)
                                .font(Typography.mono(size: 12))
                                .foregroundStyle(Palette.textPrimary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 160)
            }
        }
    }

    private func remove() {
        let command = PluginCommand.removeMarketplace(name: marketplace.name, scope: marketplace.removalScope(scope))
        failure = nil
        removing = Task {
            defer { removing = nil }
            do {
                let result = try await catalog.perform(command)
                if result.succeeded {
                    dismiss()
                } else {
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
