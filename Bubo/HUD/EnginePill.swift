import SwiftUI

/// The pill at the top of the HUD during onboarding: the Motore principale that will answer (ADR 0014), its version,
/// and how it is paid for or whose account it uses.
struct EnginePill: View {
    private let label: Text

    /// The pill of `claude`, as `readiness` found it.
    init(claude readiness: ClaudeReadiness) {
        label = switch readiness {
        case let .ready(version, method): Text(verbatim: "claude \(version) · \(method)")
        case .missing: Text("claude non trovata")
        case let .signedOut(version): Text("claude \(version) · senza accesso")
        case let .outdated(version): Text("claude \(version) · da aggiornare")
        }
    }

    /// The pill of `copilot`, as `readiness` found it.
    init(copilot readiness: CopilotReadiness) {
        label = switch readiness {
        case let .ready(version, account?): Text(verbatim: "copilot \(version) · \(account)")
        case let .ready(version, nil): Text(verbatim: "copilot \(version)")
        case .missing: Text("copilot non trovato")
        case let .signedOut(version): Text("copilot \(version) · senza accesso")
        case let .free(version, _): Text("copilot \(version) · Copilot Free")
        }
    }

    var body: some View {
        label
            .font(Typography.mono(size: 11))
            .foregroundStyle(Palette.textSecondary)
            .padding(.horizontal, Spacing.xSmall)
            .padding(.vertical, Spacing.xxSmall)
            .overlay(Capsule().strokeBorder(Palette.line))
    }
}

#Preview {
    VStack {
        EnginePill(claude: .ready(version: "2.1.286", method: "Max"))
        EnginePill(claude: .missing)
        EnginePill(claude: .outdated(version: "2.0.9"))
        EnginePill(copilot: .ready(version: "1.0.16", account: "ada"))
        EnginePill(copilot: .signedOut(version: "1.0.16"))
    }
    .padding()
    .background(Palette.ink)
}
