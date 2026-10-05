import AppKit
import SwiftUI

/// What to do when a Motore of the step is not ready: why, the command to copy into the Terminal, and «Riprova», which
/// asks `claude` and `copilot` again. A `claude` without login can answer with an API key instead, as in the remedy
/// under the Orb (ADR 0003).
struct EngineRemedy: View {
    let flow: OnboardingFlow
    let engine: Session.Engine
    /// The command for the executable Bubo found; `nil` until found, or when the remedy has none.
    @State private var command: String?
    @State private var isEnteringKey = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Text(message)
                .font(Typography.body(size: 12))
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let command {
                Text(verbatim: command)
                    .font(Typography.mono(size: 12))
                    .foregroundStyle(Palette.textPrimary)
                    .textSelection(.enabled)
                    .padding(Spacing.xSmall)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.ink, in: .rect(cornerRadius: CornerRadius.medium))
            }
            HStack(spacing: Spacing.small) {
                if let command {
                    Button("Copia il comando") { copy(command) }
                }
                Button("Riprova") { Task { await flow.recheckEngines() } }
                    .disabled(flow.isRecheckingEngines)
                    .help("Bubo controlla di nuovo Claude Code e Copilot su questo Mac.")
                if flow.isRecheckingEngines {
                    ProgressView().controlSize(.small)
                        .accessibilityLabel("Controllo…")
                }
                if offersAPIKey {
                    Button("Uso una API key") { isEnteringKey.toggle() }
                        .buttonStyle(.link)
                        .accessibilityAddTraits(isEnteringKey ? .isSelected : [])
                }
            }
            if offersAPIKey { APIKeyField(flow: flow, isEntering: $isEnteringKey) }
        }
        .accessibilityElement(children: .contain)
        .task(id: Key(claude: flow.readiness, copilot: flow.copilotReadiness)) { command = await findCommand() }
    }

    /// What the remedy depends on: it changes at each «Riprova».
    private struct Key: Equatable {
        let claude: ClaudeReadiness?
        let copilot: CopilotReadiness?
    }

    /// Whether the user may give `claude` an API key instead of signing in.
    private var offersAPIKey: Bool {
        guard engine == .claude, case .signedOut = flow.readiness else { return false }
        return true
    }

    private var message: LocalizedStringResource {
        switch engine {
        case .claude:
            switch flow.readiness {
            case .signedOut:
                "Claude Code è installato, ma non hai fatto l'accesso. Accedi nel Terminale con questo comando, poi premi Riprova."
            case .outdated:
                "Questa versione di Claude Code è troppo vecchia per Bubo. Aggiornala nel Terminale con questo comando, poi premi Riprova."
            default:
                "Claude Code non è su questo Mac. Installalo nel Terminale con questo comando, poi premi Riprova."
            }
        case .copilot:
            switch flow.copilotReadiness {
            case .signedOut:
                "Copilot CLI è installato, ma non hai fatto l'accesso. Accedi nel Terminale con questo comando, poi premi Riprova."
            case .free:
                "Con il piano Copilot Free, Bubo non può scegliere il modello. Passa a un piano a pagamento su GitHub, poi premi Riprova."
            default:
                "Copilot CLI non è su questo Mac. Installalo con Homebrew: incolla questo comando nel Terminale, poi premi Riprova."
            }
        }
    }

    /// The command for this remedy, with the full path of the executable Bubo found: the Terminal must reach the same
    /// one that will answer.
    private func findCommand() async -> String? {
        switch engine {
        case .claude:
            switch flow.readiness {
            case .signedOut:
                return await ClaudeLocator().executableURL().map(RemedyCommand.login(claude:)) ?? "claude auth login"
            case .outdated:
                guard let claude = await ClaudeLocator().executableURL() else { return nil }
                return RemedyCommand.update(claude: claude, installation: claude.resolvingSymlinksInPath())
            default:
                return RemedyCommand.install
            }
        case .copilot:
            switch flow.copilotReadiness {
            case .signedOut:
                return await CopilotLocator().executableURL().map(RemedyCommand.loginCopilot) ?? "copilot login"
            case .free:
                return nil
            default:
                return RemedyCommand.installCopilot
            }
        }
    }

    private func copy(_ command: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        AccessibilityNotification.Announcement(String(localized: "Comando copiato")).post()
    }
}
