import SwiftUI

/// Settings › Account: the Claude login, read from and changed through the `claude` CLI.
struct AccountSettingsView: View {
    @Environment(ClaudeAccount.self) private var account
    @State private var confirmsLogOut = false

    var body: some View {
        Form {
            Section {
                content
            } footer: {
                Text("Bubo usa il login di Claude Code e non vede mai password né token.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task { await account.refresh() }
        .confirmationDialog("Uscire da Claude?", isPresented: $confirmsLogOut) {
            Button("Esci", role: .destructive) { Task { await account.logOut() } }
        } message: {
            Text("Le Sessioni si fermano finché non accedi di nuovo. Vale anche per `claude` nel Terminale.")
        }
    }

    @ViewBuilder private var content: some View {
        switch account.status {
        case nil:
            ProgressView("Controllo l'account…")
        case .connected(let email, let plan):
            row(plan.map { Text("Collegato come \(email) · \($0.capitalized)") } ?? Text("Collegato come \(email)")) {
                Button("Esci…") { confirmsLogOut = true }
            }
        case .notConnected:
            row(Text("Non collegato")) {
                logInButton("Accedi con Claude")
            }
            Text("Si apre il browser sulla pagina di accesso di Anthropic.")
                .font(.callout)
                .foregroundStyle(.secondary)
        case .expired:
            row(Text("Il login è scaduto")) {
                logInButton("Accedi di nuovo")
            }
        case .cliMissing:
            row(Text("Claude Code non è installato")) {
                retryButton
            }
            Text("Installalo dal Terminale, poi scegli Riprova:")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(verbatim: "curl -fsSL https://claude.ai/install.sh | bash")
                .font(.callout.monospaced())
                .textSelection(.enabled)
        case .offline:
            row(Text("Sei offline")) {
                retryButton
            }
            Text("Claude risponde quando torna la rete. Bubo non passa alla API key.")
                .font(.callout)
                .foregroundStyle(.secondary)
        case .unknown(let detail):
            row(Text("Non riesco a leggere lo stato dell'account")) {
                retryButton
            }
            Text(verbatim: detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    /// A status line with its action on the trailing edge; the button keeps its own VoiceOver label.
    private func row(_ status: Text, @ViewBuilder action: () -> some View) -> some View {
        HStack {
            status
            Spacer()
            action()
        }
    }

    private func logInButton(_ title: LocalizedStringKey) -> some View {
        Button(title) { Task { await account.logIn() } }
            .disabled(account.isBusy)
    }

    private var retryButton: some View {
        Button("Riprova") { Task { await account.refresh() } }
            .disabled(account.isBusy)
    }
}
