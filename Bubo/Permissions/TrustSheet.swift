import SwiftUI

/// The trust dialog before the first Sessione in a folder that is not trusted (#266).
///
/// It lists what the repo would turn on, verbatim and escaped. Fidati writes the trust in
/// `~/.claude.json`; Non ora starts with the user's settings only and asks again next time.
// ponytail: opens at the first Sessione once Sessioni exist (#69); Revoca goes in the Progetto's settings, which
// call `TrustGate.revoke(_:)`.
struct TrustSheet: View {
    /// The folder the Sessione will run in.
    let folder: URL
    /// What the folder would turn on.
    let activations: RepoActivations
    /// Starts the Sessione, after either choice.
    let start: () -> Void
    var gate = TrustGate()
    @Environment(\.dismiss) private var dismiss
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            Form {
                Section {
                    Text(verbatim: RepoActivations.escaped(folder.path))
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                } header: {
                    Text("Ti fidi di questa cartella?")
                } footer: {
                    Text("Se ti fidi, Claude usa le impostazioni del repo, che possono eseguire comandi sul tuo Mac.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if activations.isEmpty {
                    Text("Il repo non attiva nulla.")
                        .foregroundStyle(.secondary)
                } else {
                    entries("Hook", activations.hooks)
                    entries("Variabili d'ambiente", activations.environment)
                    entries("apiKeyHelper", activations.apiKeyHelper.map { [$0] } ?? [])
                    entries("Server MCP", activations.mcpServers)
                    entries("Azioni consentite", activations.allowRules)
                    entries("Cartelle aggiuntive", activations.additionalDirectories)
                }
            }
            .formStyle(.grouped)

            if failed {
                ErrorNotice("Non riesco a salvare la fiducia", remedy: "Controlla ~/.claude.json, poi riprova.",
                            actionTitle: "Riprova", action: trust)
            }
            HStack {
                Spacer()
                Button("Non ora") {
                    start()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                // No default shortcut: Return must never trust a repo by accident.
                Button("Fidati", action: trust)
            }
        }
        .padding(Spacing.medium)
        .frame(width: 520)
        .frame(maxHeight: 640)
    }

    @ViewBuilder
    private func entries(_ title: LocalizedStringKey, _ lines: [String]) -> some View {
        if !lines.isEmpty {
            Section(title) {
                ForEach(lines.indices, id: \.self) { index in
                    Text(verbatim: lines[index])
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func trust() {
        do {
            try gate.trust(folder)
            failed = false
            start()
            dismiss()
        } catch {
            failed = true
        }
    }
}

#Preview {
    TrustSheet(folder: URL(filePath: "/Users/u/Sviluppo/repo"),
               activations: RepoActivations(hooks: ["SessionStart: ./scripts/setup.sh"], environment: ["DEBUG"],
                                            mcpServers: [#"db: npx -y @acme/mcp-db\u{202E}"#],
                                            allowRules: ["Bash(npm test:*)"]),
               start: {})
}
