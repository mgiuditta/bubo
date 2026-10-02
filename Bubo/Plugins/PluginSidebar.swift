import SwiftUI

/// The Plugin window's sidebar: the Progetto, Installati, Da sistemare when it has something, the Marketplaces with
/// what adds and removes them.
///
/// Nothing is registered without a click: the official Marketplace, when missing, is a row with Aggiungi (spec 20).
struct PluginSidebar: View {
    let snapshot: PluginSnapshot?
    let project: URL?
    /// How many MCP servers wait for a login: they count in Da sistemare.
    let serversNeedingAuthentication: Int
    /// The installed plugins with a newer version.
    let updates: [PluginID: PluginUpdate]
    @Binding var selection: PluginSidebarItem?
    /// The source of the Marketplace being added from a row, while `claude` works.
    let addingSource: String?
    /// Asks for another Progetto.
    let chooseProject: () -> Void
    /// Adds the Marketplace at a source in one click: the official or the community one.
    let add: (String) -> Void
    /// Opens the Aggiungi marketplace sheet.
    let addOther: () -> Void
    /// Opens the confirmation that removes a Marketplace.
    let remove: (Marketplace) -> Void

    var body: some View {
        List(selection: $selection) {
            PluginSidebarLabel("Installati", systemImage: "puzzlepiece.extension")
                .tag(PluginSidebarItem.installed)
            let toFix = Set(snapshot?.problems.map(\.plugin) ?? []).count + serversNeedingAuthentication
            if toFix > 0 {
                PluginSidebarLabel("Da sistemare", systemImage: "wrench.adjustable", count: toFix)
                    .tag(PluginSidebarItem.toFix)
            }
            PluginSidebarLabel("Aggiornamenti", systemImage: "arrow.down.circle", count: updates.isEmpty ? nil : updates.count,
                               countLabel: Text("\(updates.count) aggiornamenti"))
                .tag(PluginSidebarItem.updates)
            PluginSidebarLabel("Server MCP", systemImage: "server.rack")
                .tag(PluginSidebarItem.mcpServers)
            if let snapshot {
                Section("Marketplace") {
                    ForEach(snapshot.marketplaces) { marketplace in
                        PluginSidebarLabel(verbatim: marketplace.name, systemImage: "storefront",
                                           hasUpdates: updates.keys.contains { $0.marketplace == marketplace.name })
                            .tag(PluginSidebarItem.marketplace(marketplace.name))
                            .contextMenu {
                                if marketplace.isRemovable {
                                    Button("Rimuovi marketplace…") { remove(marketplace) }
                                }
                            }
                    }
                    if snapshot.marketplace(named: Marketplace.official.name) == nil {
                        officialRow
                    }
                    if snapshot.marketplace(named: Marketplace.community.name) == nil {
                        addButton("Community", source: Marketplace.community.source)
                    }
                    Button("Aggiungi marketplace…", systemImage: "plus", action: addOther)
                        .buttonStyle(.borderless)
                        .disabled(addingSource != nil)
                }
            }
        }
        .safeAreaInset(edge: .top) { header }
    }

    /// The official Marketplace, missing: registered only with this click.
    private var officialRow: some View {
        HStack {
            Text("Marketplace ufficiale di Anthropic")
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if addingSource == Marketplace.official.source {
                LoadingLabel("Aggiungo…")
            } else {
                Button("Aggiungi") { add(Marketplace.official.source) }
                    .controlSize(.small)
                    .disabled(addingSource != nil)
            }
        }
    }

    @ViewBuilder
    private func addButton(_ title: LocalizedStringKey, source: String) -> some View {
        if addingSource == source {
            LoadingLabel("Aggiungo…")
        } else {
            Button(title, systemImage: "plus") { add(source) }
                .buttonStyle(.borderless)
                .disabled(addingSource != nil)
        }
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
