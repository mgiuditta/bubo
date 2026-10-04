import AppKit
import SwiftUI

/// The remedy under the Orb when `claude` is not ready (spec 26): missing, signed out or outdated, also when a
/// Sessione finds it too old after the onboarding (spec 27); or when the first Sessione did not answer: a refused
/// credential, no network, no first token in time.
///
/// Never a window or a sheet. The Terminal opens on a `.command` file, with no Apple Events; the API key goes in a
/// secure field here, into the keychain. The question waiting stays, and starts on its own once `claude` is ready.
struct FixCard: View {
    let flow: OnboardingFlow
    /// Whether Sessioni wait for `claude` to be updated, and start on their own once it is.
    var holdsSessions = false
    @State private var isEnteringKey = false
    @State private var key = ""
    /// Whether a key is already in the keychain; `nil` until read.
    @State private var hasSavedKey: Bool?
    /// Why the last action failed, if it did. Never contains the key.
    @State private var failure: String?
    /// The command that updates the `claude` Bubo found; `nil` until found, or when it is not outdated.
    @State private var updateCommand: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Text(title)
                .font(Typography.body(size: 16))
                .foregroundStyle(Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(Typography.body(size: 13))
                .foregroundStyle(Palette.textSecondary)
            if flow.readiness == .missing {
                command(RemedyCommand.install)
            } else if isOutdated, let updateCommand {
                command(updateCommand)
            }
            actions
            if isEnteringKey { keyField }
            notes
        }
        .padding(Spacing.medium)
        .frame(maxWidth: 560, alignment: .leading)
        .background(Palette.surface, in: .rect(cornerRadius: CornerRadius.large))
        .overlay { RoundedRectangle(cornerRadius: CornerRadius.large).strokeBorder(Palette.line) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.fixCard")
        .onAppear { AccessibilityNotification.Announcement(title).post() }
        .onChange(of: title) { _, title in AccessibilityNotification.Announcement(title).post() }
        .task(id: flow.readiness) {
            guard isOutdated, let claude = await ClaudeLocator().executableURL() else { return }
            updateCommand = RemedyCommand.update(claude: claude, installation: claude.resolvingSymlinksInPath())
        }
    }

    private func command(_ text: String) -> some View {
        Text(verbatim: text)
            .font(Typography.mono(size: 12))
            .foregroundStyle(Palette.textPrimary)
            .textSelection(.enabled)
            .padding(Spacing.xSmall)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.ink, in: .rect(cornerRadius: CornerRadius.medium))
    }

    private var title: String {
        switch flow.problem {
        case .failed(.invalidKey): return String(localized: "La chiave non funziona")
        case .failed(.loginExpired): return String(localized: "Login scaduto")
        case .failed(.signedOut): return String(localized: "Accedi a Claude Code")
        case .failed(.accountWithoutClaudeCode): return String(localized: "Questo account non include Claude Code")
        case .failed(.offline): return String(localized: "Sei offline")
        case .unanswered: return String(localized: "Claude non risponde")
        case nil: break
        }
        return switch flow.readiness {
        case .signedOut: String(localized: "Accedi a Claude Code")
        case .outdated: String(localized: "Aggiorna Claude Code")
        default: String(localized: "Serve Claude Code")
        }
    }

    private var message: String {
        switch flow.problem {
        case .failed(.invalidKey):
            return String(localized: "Claude ha rifiutato la API key: forse non è valida o è senza credito. Cambiala o accedi con l'abbonamento, poi la tua domanda riparte da sola.")
        case .failed(.loginExpired):
            return String(localized: "Claude Code chiede un nuovo accesso. Si fa nel Terminale, poi la tua domanda riparte da sola.")
        case .failed(.signedOut):
            return String(localized: "Claude Code non ha nessun accesso. Si fa nel Terminale, poi la tua domanda riparte da sola.")
        case .failed(.accountWithoutClaudeCode):
            return String(localized: "Questo account non può usare Claude Code. Controlla il piano su claude.ai, oppure accedi con un altro account o usa una API key: la tua domanda riparte da sola.")
        case .failed(.offline):
            return String(localized: "Claude non è raggiungibile da questo Mac. Controlla la connessione e premi Riprova: la tua domanda è ancora qui.")
        case .unanswered:
            return String(localized: "Non è ancora arrivata nessuna risposta. Riprova, oppure usa Diagnostica per controllare Claude Code nel Terminale.")
        case nil: break
        }
        return switch flow.readiness {
        case .signedOut:
            String(localized: "Claude Code è installato ma non hai ancora fatto l'accesso. Accedi nel Terminale: Bubo se ne accorge da solo.")
        case .outdated(""):
            String(localized: "Questa versione di Claude Code è troppo vecchia per Bubo. Aggiornala nel Terminale.")
        case let .outdated(version):
            String(localized: "La versione \(version) di Claude Code è troppo vecchia per Bubo. Aggiornala nel Terminale.")
        default:
            String(localized: "Bubo risponde con Claude Code, che non è su questo Mac. Installalo dal Terminale con questo comando:")
        }
    }

    private var actions: some View {
        HStack(spacing: Spacing.small) {
            if let problem = flow.problem {
                remedies(for: problem)
            } else {
                readinessActions
            }
        }
    }

    @ViewBuilder private func remedies(for problem: OnboardingFlow.Problem) -> some View {
        switch problem {
        case .failed(.invalidKey):
            Button("Cambia chiave", action: toggleKeyField)
                .buttonStyle(.borderedProminent)
                .accessibilityAddTraits(isEnteringKey ? .isSelected : [])
            Button("Accedi con l'abbonamento", action: signInAgain)
        case .failed(.loginExpired):
            Button("Accedi di nuovo", action: signInAgain)
                .buttonStyle(.borderedProminent)
        case .failed(.signedOut):
            Button("Accedi nel Terminale", action: signInAgain)
                .buttonStyle(.borderedProminent)
        case .failed(.accountWithoutClaudeCode):
            Button("Accedi con un altro account", action: signInAgain)
                .buttonStyle(.borderedProminent)
            if !flow.usesAPIKey { apiKeyButton }
        case .failed(.offline):
            Button("Riprova", action: flow.askAgain)
                .buttonStyle(.borderedProminent)
        case .unanswered:
            Button("Riprova", action: flow.askAgain)
                .buttonStyle(.borderedProminent)
            Button("Diagnostica") { openTerminal(RemedyCommand.doctor) }
                .help("Scrive claude doctor nel Terminale: premi Invio per avviarlo.")
        }
    }

    @ViewBuilder private var readinessActions: some View {
        switch flow.readiness {
        case .signedOut:
            Button("Accedi nel Terminale") { openTerminal(RemedyCommand.login) }
                .buttonStyle(.borderedProminent)
        case .outdated:
            Button("Aggiorna nel Terminale") {
                openTerminal { RemedyCommand.update(claude: $0, installation: $0.resolvingSymlinksInPath()) }
            }
            .buttonStyle(.borderedProminent)
        default:
            Button("Installa nel Terminale", action: copyAndOpenTerminal)
                .buttonStyle(.borderedProminent)
            Button("Riprova") { Task { await flow.recheck() } }
                .help("Se l'hai già installato, Bubo lo cerca di nuovo.")
        }
        if !isOutdated && !flow.usesAPIKey { apiKeyButton }
    }

    private var apiKeyButton: some View {
        Button("Uso una API key", action: toggleKeyField)
            .buttonStyle(.link)
            .accessibilityAddTraits(isEnteringKey ? .isSelected : [])
    }

    /// Shows or hides the field for the API key, finding out whether one is already saved.
    private func toggleKeyField() {
        isEnteringKey.toggle()
        Task { hasSavedKey = try? await APIKeyStore().containsKey() }
    }

    /// Opens the Terminal on the login of `claude`; the first question asks again when the user is back.
    private func signInAgain() {
        flow.signInAgain()
        openTerminal(RemedyCommand.login)
    }

    private var keyField: some View {
        HStack(spacing: Spacing.small) {
            SecureField("API key", text: $key)
                .textFieldStyle(.roundedBorder)
                .onSubmit(saveKey)
                .accessibilityLabel("API key")
            Button("Salva", action: saveKey)
                .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            // A refused key is the one Bubo used: offering it again would not help.
            if hasSavedKey == true && !flow.usesAPIKey {
                Button("Usa quella salvata") { Task { await flow.useAPIKey() } }
            }
        }
    }

    @ViewBuilder private var notes: some View {
        if isEnteringKey && (!flow.usesAPIKey || flow.problem != nil) {
            Text("La chiave resta nel Portachiavi di questo Mac e si paga a consumo.")
                .font(Typography.body(size: 12))
                .foregroundStyle(Palette.textSecondary)
        }
        if flow.usesAPIKey && flow.readiness == .missing {
            Text("La API key è salvata, ma serve comunque Claude Code.")
                .font(Typography.body(size: 12))
                .foregroundStyle(Palette.textSecondary)
        }
        if holdsSessions {
            Text("Bubo avvia le Sessioni in attesa appena Claude Code è aggiornato.")
                .font(Typography.body(size: 12))
                .foregroundStyle(Palette.textSecondary)
        }
        if flow.pendingQuestion != nil && flow.problem == nil {
            Text("La tua domanda aspetta qui e parte da sola appena Claude Code è pronto.")
                .font(Typography.body(size: 12))
                .foregroundStyle(Palette.textSecondary)
        }
        if let failure {
            Text(failure)
                .font(Typography.body(size: 12))
                .foregroundStyle(Palette.danger)
        }
    }

    /// Whether `claude` is too old: an API key would not help.
    private var isOutdated: Bool {
        if case .outdated = flow.readiness { true } else { false }
    }

    /// Copies the installer's command and opens the Terminal with it typed: the user runs it.
    private func copyAndOpenTerminal() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(RemedyCommand.install, forType: .string)
        open(RemedyCommand.install)
    }

    /// Opens the Terminal on the command for the `claude` Bubo found.
    private func openTerminal(_ command: @escaping (URL) -> String) {
        Task {
            guard let claude = await ClaudeLocator().executableURL() else {
                await flow.recheck()
                return
            }
            open(command(claude))
        }
    }

    private func open(_ command: String) {
        do {
            try SystemTerminal().open(typing: command)
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
    }

    /// Saves the key in the keychain and answers with it from now on.
    private func saveKey() {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        Task {
            do {
                try await APIKeyStore().save(key)
                self.key = ""
                failure = nil
                isEnteringKey = false
                await flow.useAPIKey()
            } catch {
                failure = error.localizedDescription
            }
        }
    }
}

#Preview {
    let flow = OnboardingFlow(hasSessions: false, defaults: UserDefaults(suiteName: "preview") ?? .standard) { _, _ in UUID() }
    flow.readiness = .missing
    return FixCard(flow: flow)
        .padding()
        .background(Palette.ink)
}
