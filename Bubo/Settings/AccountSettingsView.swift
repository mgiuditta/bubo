import SwiftUI

/// The Claude account, read from the user's `claude` CLI.
struct AccountSettingsView: View {
    @State private var account = AccountModel()
    /// Set while a login runs; clearing it cancels the login.
    @State private var signInAttempt: UUID?
    @State private var isConfirmingSignOut = false
    @State private var isEnteringAPIKey = false
    @State private var isConfirmingKeyRemoval = false

    var body: some View {
        Form {
            Section {
                if account.isSigningIn {
                    signingIn
                } else if let state = account.state {
                    content(for: state)
                } else {
                    LoadingLabel("Controllo l'account…")
                }
                if let failure = account.failure {
                    Text(failure)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Claude")
            } footer: {
                Text("Bubo usa il login della CLI claude e non vede mai i tuoi token.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            apiKeySection
        }
        .formStyle(.grouped)
        .task { await account.refresh() }
        .task { await account.refreshAPIKey() }
        .sheet(isPresented: $isEnteringAPIKey) {
            APIKeySheet { key in
                Task { await account.saveAPIKey(key) }
            }
        }
        .task(id: signInAttempt) {
            guard signInAttempt != nil else { return }
            await account.signIn()
            signInAttempt = nil
        }
        .confirmationDialog("Vuoi uscire dall'account Claude?", isPresented: $isConfirmingSignOut) {
            Button("Esci", role: .destructive) {
                Task { await account.signOut() }
            }
        } message: {
            Text("Esce anche dalla CLI claude, in ogni terminale.")
        }
    }

    @ViewBuilder
    private func content(for state: AccountState) -> some View {
        switch state {
        case .signedIn(let email, let plan):
            Label(signedInText(email: email, plan: plan), systemImage: "checkmark.circle")
            Button("Esci…") { isConfirmingSignOut = true }
        case .signedOut:
            Label("Non sei collegato.", systemImage: "person.crop.circle.badge.questionmark")
            Button("Accedi con Claude") { signInAttempt = UUID() }
                .buttonStyle(.borderedProminent)
        case .expired:
            Label("L'accesso è scaduto.", systemImage: "exclamationmark.triangle")
            Button("Accedi di nuovo") { signInAttempt = UUID() }
                .buttonStyle(.borderedProminent)
        case .cliMissing:
            Label("Manca la CLI claude.", systemImage: "terminal")
            Text("Installala dal Terminale con `curl -fsSL https://claude.ai/install.sh | bash`, poi torna qui.")
                .textSelection(.enabled)
            retryButton
        case .offline:
            Label("Sei offline.", systemImage: "wifi.slash")
            Text("Bubo non passa da solo alla API key: riprova quando torna la rete.")
            retryButton
        case .unknownError(let exitCode):
            Label("claude ha risposto in modo inatteso (codice \(exitCode)).", systemImage: "questionmark.circle")
            retryButton
        }
    }

    private var apiKeySection: some View {
        Section {
            switch account.hasAPIKey {
            case true?:
                Label("API key salvata nel Portachiavi", systemImage: "key")
                Button("Rimuovi…") { isConfirmingKeyRemoval = true }
                    .confirmationDialog("Vuoi rimuovere la API key?", isPresented: $isConfirmingKeyRemoval) {
                        Button("Rimuovi", role: .destructive) {
                            Task { await account.removeAPIKey() }
                        }
                    } message: {
                        Text("La cancella dal Portachiavi di questo Mac.")
                    }
            case false?:
                Button("Usa una API key…") { isEnteringAPIKey = true }
                    .buttonStyle(.link)
            case nil:
                EmptyView()
            }
            if let failure = account.apiKeyFailure {
                Text(failure)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("API key")
        } footer: {
            Text("Facoltativa, per quando l'abbonamento non basta. Bubo non la usa mai da solo.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var signingIn: some View {
        HStack {
            LoadingLabel("Completa l'accesso nel browser.")
            Spacer()
            Button("Annulla") { signInAttempt = nil }
        }
    }

    private var retryButton: some View {
        Button("Riprova") {
            Task { await account.refresh() }
        }
    }

    private func signedInText(email: String?, plan: String?) -> String {
        switch (email, plan) {
        case let (email?, plan?): String(localized: "Collegato come \(email) · \(plan)")
        case let (email?, nil): String(localized: "Collegato come \(email)")
        default: String(localized: "Collegato")
        }
    }
}
