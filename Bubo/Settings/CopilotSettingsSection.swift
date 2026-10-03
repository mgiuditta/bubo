import AppKit
import SwiftUI

/// GitHub Copilot in Impostazioni › Modelli: whether the user's `copilot` can answer, and the Terminal commands that
/// install it or sign it in (ADR 0011, ADR 0012). Bubo never signs `copilot` out: the section explains how.
struct CopilotSettingsSection: View {
    /// Asks the user's `copilot` whether it can answer.
    var detect: @Sendable () async -> CopilotReadiness = { await CopilotReadiness.detect() }
    @State private var readiness: CopilotReadiness?
    /// Changing it checks `copilot` again.
    @State private var check = UUID()
    @State private var isExplainingSignOut = false
    @State private var failure: String?

    var body: some View {
        Section {
            if let readiness {
                content(for: readiness)
            } else {
                LoadingLabel("Controllo Copilot…")
            }
            if let failure {
                Text(failure)
                    .font(.callout)
                    .foregroundStyle(Palette.danger)
            }
        } header: {
            Text(verbatim: "GitHub Copilot")
        } footer: {
            Text("Bubo usa il login della CLI copilot e non vede mai i tuoi token.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .task(id: check) {
            readiness = await detect()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Back from the Terminal: the install or the login may be done.
            if readiness != nil, !Self.isSignedIn(readiness) { recheck() }
        }
        .alert("Come scollegare Copilot", isPresented: $isExplainingSignOut) {
            Button("OK") {}
        } message: {
            Text("Nel Terminale avvia copilot e scrivi /logout. Vale per la CLI copilot in ogni terminale.")
        }
    }

    @ViewBuilder
    private func content(for readiness: CopilotReadiness) -> some View {
        Label(Self.status(of: readiness), systemImage: Self.symbol(of: readiness))
        switch readiness {
        case .missing:
            Text("Installala dal Terminale con Homebrew, poi torna qui.")
            Button("Installa nel Terminale") { open(RemedyCommand.installCopilot) }
                .buttonStyle(.borderedProminent)
            retryButton
        case .signedOut:
            Button("Collega Copilot", action: signIn)
                .buttonStyle(.borderedProminent)
                .help("Scrive copilot login nel Terminale: premi Invio per avviarlo.")
            retryButton
        case .free:
            Text("Bubo non può usare Copilot Free: con quel piano il modello lo sceglie GitHub. Serve un piano a pagamento.")
                .font(.callout)
                .foregroundStyle(.secondary)
            signOutButton
            retryButton
        case .ready:
            signOutButton
        }
    }

    private var signOutButton: some View {
        Button("Scollega…") { isExplainingSignOut = true }
    }

    private var retryButton: some View {
        Button("Riprova", action: recheck)
    }

    private func recheck() {
        readiness = nil
        check = UUID()
    }

    /// Opens the Terminal on `copilot login`, for the `copilot` Bubo found.
    private func signIn() {
        Task {
            guard let copilot = await CopilotLocator().executableURL() else {
                recheck()
                return
            }
            open(RemedyCommand.loginCopilot(copilot))
        }
    }

    /// Opens the Terminal with `command` typed: the user runs it.
    private func open(_ command: String) {
        do {
            try SystemTerminal().open(typing: command)
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
    }

    /// What `readiness` means for the user, as the section's first row says it.
    static func status(of readiness: CopilotReadiness) -> String {
        switch readiness {
        case .missing:
            String(localized: "Manca la CLI copilot.")
        case .signedOut:
            String(localized: "Copilot non è collegato.")
        case .free(_, let account?):
            String(localized: "Collegato come \(account) con Copilot Free")
        case .free(_, nil):
            String(localized: "Collegato con Copilot Free")
        case .ready(_, let account?):
            String(localized: "Collegato come \(account)")
        case .ready(_, nil):
            String(localized: "Collegato")
        }
    }

    /// The symbol beside ``status(of:)``.
    private static func symbol(of readiness: CopilotReadiness) -> String {
        switch readiness {
        case .missing: "terminal"
        case .signedOut: "person.crop.circle.badge.questionmark"
        case .free: "exclamationmark.triangle"
        case .ready: "checkmark.circle"
        }
    }

    /// Whether `copilot` has a login, paid or not.
    private static func isSignedIn(_ readiness: CopilotReadiness?) -> Bool {
        switch readiness {
        case .free?, .ready?: true
        case .missing?, .signedOut?, nil: false
        }
    }
}

#Preview {
    Form {
        CopilotSettingsSection { .free(version: "1.0.0", account: "octocat") }
    }
    .formStyle(.grouped)
    .frame(width: 480, height: 300)
}
