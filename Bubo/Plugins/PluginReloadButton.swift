import SwiftUI

/// Ricarica plugin for one turn in progress with the plugins of before (spec 20), on the Sessione's row in the HUD and
/// in the Plugin window's banner.
struct PluginReloadButton: View {
    /// Where the turn is with Ricarica plugin.
    let state: PluginReloader.State
    /// Reloads, or reloads anyway once `claude` held it.
    let reload: () -> Void

    var body: some View {
        HStack(spacing: Spacing.xSmall) {
            Label("Plugin di prima", systemImage: "puzzlepiece.extension")
                .font(Typography.mono(size: 11))
                .foregroundStyle(Palette.textPrimary)
                .help("Il turno in corso usa i plugin di prima delle ultime modifiche. Il prossimo turno prende quelli nuovi da solo.")
            Button(action: reload) {
                switch state {
                case .outdated: Text("Ricarica plugin")
                case .reloading: Text("Ricarico i plugin…")
                case .held: Text("Ricarica comunque (cache del prompt persa)")
                }
            }
            .controlSize(.small)
            .disabled(state == .reloading)
            .help(help)
        }
    }

    /// What the button does, and for Ricarica comunque what changes.
    private var help: Text {
        guard case let .held(impact) = state else {
            return Text("Ricaricare può invalidare la cache del prompt: in quel caso Claude si ferma e chiede conferma.")
        }
        let servers = (impact?.added ?? []) + (impact?.removed ?? [])
        if servers.isEmpty {
            return Text("Claude non ha ricaricato per non perdere la cache del prompt. Ricarica comunque la perde: il resto del turno costa più token.")
        }
        return Text("Claude non ha ricaricato per non perdere la cache del prompt. Ricarica comunque la perde: il resto del turno costa più token. Server MCP che cambiano: \(servers.formatted(.list(type: .and))).")
    }
}

#Preview {
    VStack(alignment: .leading) {
        PluginReloadButton(state: .outdated) {}
        PluginReloadButton(state: .reloading) {}
        PluginReloadButton(state: .held(PluginReload.CacheImpact(added: ["plugin:linear:linear"], removed: []))) {}
    }
    .padding()
    .background(Palette.ink)
}
