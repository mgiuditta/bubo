import SwiftUI

/// The Plugin window's sidebar: the Progetto, Installati, Da sistemare when it has something, the Marketplaces.
struct PluginSidebar: View {
    let snapshot: PluginSnapshot?
    let project: URL?
    @Binding var selection: PluginSidebarItem?
    /// Asks for another Progetto.
    let chooseProject: () -> Void

    var body: some View {
        List(selection: $selection) {
            PluginSidebarLabel("Installati", systemImage: "puzzlepiece.extension")
                .tag(PluginSidebarItem.installed)
            if let problems = snapshot?.problems, !problems.isEmpty {
                PluginSidebarLabel("Da sistemare", systemImage: "wrench.adjustable",
                                   count: Set(problems.map(\.plugin)).count)
                    .tag(PluginSidebarItem.toFix)
            }
            if let marketplaces = snapshot?.marketplaces, !marketplaces.isEmpty {
                Section("Marketplace") {
                    ForEach(marketplaces) { marketplace in
                        PluginSidebarLabel(verbatim: marketplace.name, systemImage: "storefront")
                            .tag(PluginSidebarItem.marketplace(marketplace.name))
                    }
                }
            }
        }
        .safeAreaInset(edge: .top) { header }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
            Text("Progetto")
                .font(Typography.body(size: 11))
                .foregroundStyle(Palette.textSecondary)
            HStack {
                Text(verbatim: project?.lastPathComponent ?? "")
                    .font(Typography.body(size: 13, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(project?.path ?? "")
                Spacer(minLength: 0)
                Button(project == nil ? "Scegli cartella…" : "Cambia…", action: chooseProject)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, Spacing.small)
        .padding(.vertical, Spacing.xSmall)
    }
}
