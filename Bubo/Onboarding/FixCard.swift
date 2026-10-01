import AppKit
import SwiftUI

/// The remedy under the Orb when `claude` is not ready (spec 26): missing, signed out or outdated.
///
/// Never a window or a sheet. The Terminal opens on a `.command` file, with no Apple Events; the API key goes in a
/// secure field here, into the keychain. The question waiting stays, and starts on its own once `claude` is ready.
struct FixCard: View {
    let flow: OnboardingFlow
    @State private var isEnteringKey = false
    @State private var key = ""
    /// Whether a key is already in the keychain; `nil` until read.
    @State private var hasSavedKey: Bool?
    /// Why the last action failed, if it did. Never contains the key.
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Text(title)
                .font(Typography.body(size: 16))
                .foregroundStyle(Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(Typography.body(size: 13))
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if flow.readiness == .missing {
                Text(verbatim: RemedyCommand.install)
                    .font(Typography.mono(size: 12))
                    .foregroundStyle(Palette.textPrimary)
                    .textSelection(.enabled)
                    .padding(Spacing.xSmall)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.ink, in: .rect(cornerRadius: CornerRadius.medium))
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
    }

    private var title: String {
        switch flow.readiness {
        case .signedOut: String(localized: "Accedi a Claude Code")
        case .outdated: String(localized: "Aggiorna Claude Code")
        default: String(localized: "Serve Claude Code")
        }
    }

    private var message: String {
        switch flow.readiness {
        case .signedOut:
            String(localized: "Claude Code è installato ma non hai ancora fatto l'accesso. Accedi nel Terminale: Bubo se ne accorge da solo.")
        case let .outdated(version):
            String(localized: "La versione \(version) di Claude Code è troppo vecchia per Bubo. Aggiornala nel Terminale.")
        default:
            String(localized: "Bubo risponde con Claude Code, che non è su questo Mac. Installalo dal Terminale con questo comando:")
        }
    }

    private var actions: some View {
        HStack(spacing: Spacing.small) {
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
                Button("Copia e apri Terminale", action: copyAndOpenTerminal)
                    .buttonStyle(.borderedProminent)
                Button("Riprova") { Task { await flow.recheck() } }
                    .help("Se l'hai già installato, Bubo lo cerca di nuovo.")
            }
            if !isOutdated && !flow.usesAPIKey {
                Button("Uso una API key") {
                    isEnteringKey.toggle()
                    Task { hasSavedKey = try? await APIKeyStore().containsKey() }
                }
                .buttonStyle(.link)
                .accessibilityAddTraits(isEnteringKey ? .isSelected : [])
            }
        }
    }

    private var keyField: some View {
        HStack(spacing: Spacing.small) {
            SecureField("API key", text: $key)
                .textFieldStyle(.roundedBorder)
                .onSubmit(saveKey)
                .accessibilityLabel("API key")
            Button("Salva", action: saveKey)
                .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if hasSavedKey == true {
                Button("Usa quella salvata") { Task { await flow.useAPIKey() } }
            }
        }
    }

    @ViewBuilder private var notes: some View {
        if isEnteringKey && !flow.usesAPIKey {
            Text("La chiave resta nel Portachiavi di questo Mac e si paga a consumo.")
                .font(Typography.body(size: 12))
                .foregroundStyle(Palette.textSecondary)
        }
        if flow.usesAPIKey && flow.readiness == .missing {
            Text("La API key è salvata, ma serve comunque Claude Code.")
                .font(Typography.body(size: 12))
                .foregroundStyle(Palette.textSecondary)
        }
        if flow.pendingQuestion != nil {
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
    let flow = OnboardingFlow(hasSessions: false, defaults: UserDefaults(suiteName: "preview") ?? .standard) { _, _ in }
    flow.readiness = .missing
    return FixCard(flow: flow)
        .padding()
        .background(Palette.ink)
}
