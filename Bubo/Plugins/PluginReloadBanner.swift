import SwiftUI

/// The banner under the Plugin window's toolbar while some turns in progress have the plugins of before (spec 20,
/// #212): one Ricarica plugin per Sessione, and Ricarica tutte. Nothing when every turn has the current plugins.
struct PluginReloadBanner: View {
    /// The Sessioni, with their turns in progress and Ricarica plugin.
    let store: SessionStore

    var body: some View {
        let reloader = store.pluginReloader
        let outdated = store.sessions.filter { reloader.state(of: $0.id) != nil }
        if !outdated.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                        Text("\(outdated.count) Sessioni al lavoro usano i plugin di prima")
                            .font(Typography.body(size: 13))
                            .foregroundStyle(Palette.textPrimary)
                        Text("Ricaricare può invalidare la cache del prompt.")
                            .font(Typography.body(size: 12))
                            .foregroundStyle(Palette.textSecondary)
                    }
                    Spacer()
                    if outdated.count > 1 {
                        Button("Ricarica tutte") {
                            Task { await reloader.reloadAllPlugins() }
                        }
                        .controlSize(.small)
                        .disabled(!outdated.contains { reloader.state(of: $0.id) == .outdated })
                    }
                }
                ForEach(outdated) { session in
                    if let state = reloader.state(of: session.id) {
                        HStack(spacing: Spacing.small) {
                            Text(verbatim: session.title)
                                .font(Typography.body(size: 12))
                                .foregroundStyle(Palette.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            PluginReloadButton(state: state) {
                                Task { await reloader.reloadPlugins(in: session.id) }
                            }
                        }
                    }
                }
            }
            .padding(Spacing.small)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)
            .accessibilityElement(children: .contain)
        }
    }
}
