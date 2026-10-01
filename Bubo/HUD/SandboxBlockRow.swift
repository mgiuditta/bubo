import SwiftUI

/// One thing the Sandbox stopped a command from doing, in its Sessione (spec 22): "Bloccato dalla sandbox: …" with
/// the path or host, and Consenti in questo Progetto when the folder or host can be let in.
///
/// Consenti saves in Bubo's store, never in the settings, and counts from the next turn.
struct SandboxBlockRow: View {
    let block: SandboxBlock
    /// Whether the Progetto's Sandbox already reaches the block's folder or host.
    let isAllowed: Bool
    let allow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
            Label {
                Text(verbatim: RepoActivations.escaped(block.line))
                    .font(Typography.mono(size: 11))
                    .foregroundStyle(Palette.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "lock.shield")
                    .foregroundStyle(Palette.attention)
                    .accessibilityHidden(true)
            }
            if block.allowance != nil {
                if isAllowed {
                    Text("Consentito in questo Progetto dal prossimo turno")
                        .font(Typography.body(size: 11))
                        .foregroundStyle(Palette.textSecondary)
                } else {
                    Button("Consenti in questo Progetto", action: allow)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help(block.kind == .network
                            ? Text("Aggiunge l'host ai domini della Sandbox di questo Progetto, in Bubo. Vale dal prossimo turno.")
                            : Text("Aggiunge questa cartella a quelle in cui la Sandbox di questo Progetto scrive, in Bubo. Vale dal prossimo turno."))
                }
            }
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: Spacing.small) {
        SandboxBlockRow(block: SandboxBlock(kind: .network, target: "api.github.com"), isAllowed: false) {}
        SandboxBlockRow(block: SandboxBlock(kind: .write, target: "/Users/u/.cache/x/a.txt"), isAllowed: true) {}
        SandboxBlockRow(block: SandboxBlock(kind: .read, target: "/Users/u/.ssh/id_ed25519"), isAllowed: false) {}
    }
    .frame(width: 320)
    .padding()
    .background(Palette.ink)
}
