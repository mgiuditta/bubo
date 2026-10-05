import SwiftUI

/// One card of the step of the Motore: Claude, Copilot or Entrambi, with what Bubo found on the Mac and, for a Motore
/// not ready, the command to copy and «Riprova». Entrambi, once chosen, asks which one is the principale.
struct EngineCard: View {
    @Bindable var flow: OnboardingFlow
    let option: OnboardingFlow.EngineOption

    private var isSelected: Bool { flow.engineOption == option }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Button { flow.chooseEngine(option) } label: { header }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(title))
                .accessibilityValue(Text(status))
                .accessibilityHint(Text(subtitle))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("onboarding.engine.\(String(describing: option))")
            if option == .both && isSelected {
                Picker("Principale", selection: $flow.primaryOfBoth) {
                    Text(verbatim: "Claude").tag(Session.Engine.claude)
                    Text(verbatim: "Copilot").tag(Session.Engine.copilot)
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .padding(.leading, Spacing.large)
            }
            if let engine = remedyEngine {
                EngineRemedy(flow: flow, engine: engine)
                    .padding(.leading, Spacing.large)
            }
        }
        .padding(Spacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Palette.rowSelection : Palette.surface, in: .rect(cornerRadius: CornerRadius.large))
        .overlay {
            // Not color alone: the card chosen also has a filled radio and the trait «selected».
            RoundedRectangle(cornerRadius: CornerRadius.large).strokeBorder(isSelected ? Palette.lineStrong : Palette.line)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(isSelected ? Palette.accent : Palette.textSecondary)
            VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                Text(title)
                    .font(Typography.body(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                Text(subtitle)
                    .font(Typography.body(size: 12))
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer(minLength: Spacing.small)
            statusLabel
        }
        .contentShape(.rect)
    }

    private var statusLabel: some View {
        HStack(spacing: Spacing.xxSmall) {
            if isDetecting {
                ProgressView().controlSize(.mini)
            } else {
                Image(systemName: flow.isReady(option: option) ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .foregroundStyle(flow.isReady(option: option) ? Palette.success : Palette.textSecondary)
            }
            Text(status)
                .font(Typography.body(size: 12))
                .foregroundStyle(Palette.textSecondary)
        }
    }

    private var title: LocalizedStringResource {
        switch option {
        case .claude: "Claude"
        case .copilot: "Copilot"
        case .both: "Entrambi"
        }
    }

    private var subtitle: LocalizedStringResource {
        switch option {
        case .claude: "Claude Code di Anthropic"
        case .copilot: "GitHub Copilot CLI"
        case .both: "Uno principale, l'altro di Riserva quando finisce la quota"
        }
    }

    /// Whether Bubo is still finding out what is on the Mac for this card.
    private var isDetecting: Bool {
        switch option {
        case .claude: flow.readiness == nil
        case .copilot: flow.copilotReadiness == nil
        case .both: flow.readiness == nil || flow.copilotReadiness == nil
        }
    }

    private var status: LocalizedStringResource {
        if isDetecting { return "Controllo…" }
        switch option {
        case .claude: return Self.status(of: flow.readiness)
        case .copilot: return Self.status(of: flow.copilotReadiness)
        case .both: return flow.isReady(option: .both) ? "Pronti" : "Servono tutti e due pronti"
        }
    }

    /// The Motore whose remedy the card shows; Entrambi shows none: the two cards above have them.
    private var remedyEngine: Session.Engine? {
        switch option {
        case .claude where !isDetecting && !flow.isReady(.claude): .claude
        case .copilot where !isDetecting && !flow.isReady(.copilot): .copilot
        default: nil
        }
    }

    private static func status(of readiness: ClaudeReadiness?) -> LocalizedStringResource {
        switch readiness {
        case let .ready(_, method) where !method.isEmpty: "Pronto · \(method)"
        case .ready: "Pronto"
        case .signedOut: "Serve l'accesso"
        case .outdated: "Da aggiornare"
        case .missing, nil: "Non installato"
        }
    }

    private static func status(of readiness: CopilotReadiness?) -> LocalizedStringResource {
        switch readiness {
        case let .ready(_, account?): "Pronto · \(account)"
        case .ready: "Pronto"
        case .signedOut: "Serve l'accesso"
        case .free: "Serve un piano a pagamento"
        case .missing, nil: "Non installato"
        }
    }
}

#Preview {
    let defaults = UserDefaults(suiteName: "preview") ?? .standard
    let flow = OnboardingFlow(hasSessions: false, defaults: defaults, settings: EndpointSettings(defaults: defaults)) { _, _ in
        UUID()
    }
    flow.readiness = .signedOut(version: "2.1.286")
    flow.copilotReadiness = .ready(version: "1.0.16", account: "ada")
    flow.chooseEngine(.both)
    return VStack {
        ForEach(OnboardingFlow.EngineOption.allCases, id: \.self) { EngineCard(flow: flow, option: $0) }
    }
    .padding()
    .background(Palette.ink)
}
