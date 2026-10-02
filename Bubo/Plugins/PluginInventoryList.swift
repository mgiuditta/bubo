import SwiftUI

/// What a plugin installs, or installed, by kind, with the sign on the components that run code on the Mac.
struct PluginInventoryList: View {
    let inventory: PluginInventory
    let isInstalled: Bool
    /// The heading in place of "Cosa installa" or "Componenti installati".
    var title: Text?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            (title ?? Text(isInstalled ? "Componenti installati" : "Cosa installa"))
                .font(Typography.body(size: 13, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            ForEach(PluginComponent.Kind.allCases, id: \.self) { kind in
                let components = inventory.components.filter { $0.kind == kind }
                if !components.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                        Text(kind.title)
                            .font(Typography.body(size: 11, weight: .medium))
                            .foregroundStyle(Palette.textSecondary)
                        ForEach(components, id: \.self) { component in
                            HStack(spacing: Spacing.xxSmall) {
                                Text(verbatim: component.name)
                                    .font(Typography.mono(size: 12))
                                    .foregroundStyle(Palette.textPrimary)
                                if component.runsCode {
                                    Image(systemName: "terminal")
                                        .foregroundStyle(Palette.textSecondary)
                                        .accessibilityLabel(Text("esegue codice"))
                                        .help(Text("gira fuori dalla sandbox"))
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
