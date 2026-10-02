import SwiftUI

/// The detail of a plugin: name, Marketplace, version, state, what needs attention and its components. Read only:
/// the actions arrive with the next steps of spec 20.
struct PluginDetail: View {
    let entry: PluginEntry
    let problems: [PluginProblem]
    let marketplace: Marketplace?
    let officialCache: OfficialCatalogCache?
    @State private var inventory: PluginInventory?
    @State private var hasReadInventory = false

    /// What the inventory is read for: the entry, and whether the official cache has arrived.
    private struct InventoryKey: Equatable {
        var entry: PluginEntry
        var hasOfficialCache: Bool
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.medium) {
                header
                labels
                if !problems.isEmpty { problemList }
                if !entry.summary.isEmpty {
                    Text(verbatim: entry.summary)
                        .font(Typography.body(size: 13))
                        .foregroundStyle(Palette.textPrimary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if hasReadInventory {
                    if let inventory {
                        PluginInventoryList(inventory: inventory, isInstalled: entry.isInstalled)
                    } else {
                        Label("Componenti sconosciuti: può eseguire codice sul Mac", systemImage: "questionmark.circle")
                            .font(Typography.body(size: 12))
                            .foregroundStyle(Palette.textSecondary)
                            .padding(Spacing.small)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Palette.surface, in: .rect(cornerRadius: 8))
                    }
                }
            }
            .padding(Spacing.large)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: InventoryKey(entry: entry, hasOfficialCache: officialCache != nil)) {
            let read = await PluginInventory.inventory(of: entry, marketplace: marketplace, officialCache: officialCache)
            inventory = read
            hasReadInventory = true
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
            Text(verbatim: entry.displayName)
                .font(Typography.body(size: 20, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: Spacing.xSmall) {
                if entry.id.isSynced {
                    Text("Sincronizzato da claude.ai")
                } else {
                    Text(verbatim: entry.id.marketplace)
                }
                if let version = entry.installations.first?.version ?? entry.version {
                    Text("Versione \(version)")
                }
            }
            .font(Typography.body(size: 12))
            .foregroundStyle(Palette.textSecondary)
        }
    }

    private var labels: some View {
        HStack(spacing: Spacing.small) {
            if entry.isInstalled {
                Text(entry.isEnabled ? "Attivo" : "Disattivato")
                ForEach(Array(Set(entry.installations.map(\.scope))).sorted { $0.rawValue < $1.rawValue }, id: \.self) { scope in
                    Text(scope.title)
                }
                if inventory?.runsOutsideSandbox == true {
                    OutsideSandboxLabel()
                }
            } else if hasReadInventory {
                PluginTrustLabel(trust: PluginInventory.trust(of: inventory))
            }
        }
        .font(Typography.body(size: 11))
        .foregroundStyle(Palette.textSecondary)
    }

    private var problemList: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            ForEach(Array(problems.enumerated()), id: \.offset) { _, problem in
                Label {
                    switch problem {
                    case let .loadFailed(_, message): Text(verbatim: message)
                    case .missingProjectPlugin: Text("Plugin di Progetto non installato su questo Mac")
                    }
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(Palette.danger)
                        .accessibilityLabel(Text("Errore"))
                }
                .font(Typography.body(size: 12))
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Spacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: .rect(cornerRadius: 8))
    }
}
