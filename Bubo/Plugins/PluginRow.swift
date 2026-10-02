import SwiftUI

/// A row of the Plugin window's list: status dot, name, description, and for an entry not installed its trust label
/// and Installa….
struct PluginRow: View {
    let entry: PluginEntry
    /// Whether `claude` failed to load it.
    let failed: Bool
    let marketplace: Marketplace?
    let officialCache: OfficialCatalogCache?
    /// Opens the Installa sheet of the entry.
    let install: () -> Void
    @State private var trust: PluginTrust?
    @Environment(\.backgroundProminence) private var prominence

    /// What the trust label is worked out from: the entry, and whether the official cache has arrived.
    private struct TrustKey: Equatable {
        var id: PluginID
        var hasOfficialCache: Bool
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xSmall) {
            PluginStatusDot(status: PluginStatusDot.Status(entry, failed: failed))
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: entry.displayName)
                    .font(Typography.body(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? Palette.ink : Palette.textPrimary)
                if !entry.summary.isEmpty {
                    Text(verbatim: entry.summary)
                        .font(Typography.body(size: 12))
                        .foregroundStyle(isSelected ? Palette.ink : Palette.textSecondary)
                        .lineLimit(2)
                }
                if !entry.isInstalled, let trust {
                    PluginTrustLabel(trust: trust)
                        .foregroundStyle(isSelected ? Palette.ink : Palette.textSecondary)
                }
            }
            if !entry.isInstalled {
                Spacer(minLength: Spacing.xSmall)
                Button("Installa…", action: install)
                    .controlSize(.small)
                    .accessibilityLabel(Text("Installa \(entry.displayName)…"))
            }
        }
        .padding(.vertical, 2)
        .task(id: TrustKey(id: entry.id, hasOfficialCache: officialCache != nil)) {
            guard !entry.isInstalled else { return }
            trust = PluginInventory.trust(of: await PluginInventory.inventory(of: entry, marketplace: marketplace,
                                                                               officialCache: officialCache))
        }
    }

    private var isSelected: Bool { prominence == .increased }
}
