import SwiftUI

/// The chip under the prompt, before sending (spec 10, Interfaccia): model · effort · cost the router expects, or the
/// user picked, with the reason.
///
/// For Claude it shows no cost: a share of the 5-hour window cannot be known before the answer, and the line under
/// it says what the turn used.
struct RouterChip: View {
    let route: Route

    var body: some View {
        HStack(spacing: Spacing.xSmall) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            if let model {
                Text(verbatim: model.text)
                    .foregroundStyle(Palette.textPrimary)
                    .accessibilityLabel(model.spoken)
            }
            Text(RouterLine.reason(for: route))
                .foregroundStyle(Palette.textSecondary)
                .truncationMode(.tail)
                .layoutPriority(-1)
            if route.destination == .onDevice || route.endpoint?.isOnMac == true {
                Text("gratis, sul Mac", comment: "Cost of an answer from a model running on this Mac.")
                    .font(Typography.mono(size: 11))
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .font(Typography.body(size: 12))
        .lineLimit(1)
        .padding(.horizontal, Spacing.xSmall)
        .padding(.vertical, Spacing.xxSmall)
        .background(Palette.surface, in: .capsule)
        .overlay { Capsule().strokeBorder(Palette.line) }
        .help("Tab cambia modello, ⌥↑ e ⌥↓ lo sforzo, Esc torna al router")
        .accessibilityElement(children: .combine)
        .accessibilityHint("Tab cambia modello, Opzione e freccia su o giù cambia lo sforzo, Esc torna al router.")
        .accessibilityIdentifier("question.routerChip")
    }

    /// Anthropic's Tinta for Claude, the neutral one for the Mac, an endpoint's own.
    private var tint: Color {
        let provider: Provider? = switch route.destination {
        case .claude: .anthropic
        case .onDevice: nil
        case let .endpoint(endpoint): endpoint.provider
        case let .copilot(model): model.provider
        }
        let base = Tinta(for: provider).base
        return Color(.sRGB, red: Double(base.x), green: Double(base.y), blue: Double(base.z))
    }

    /// The model and its effort, as read and as VoiceOver says it; `nil` when `claude` picks its own default.
    private var model: (text: String, spoken: String)? {
        if route.destination == .onDevice { return (RouterLine.appleFM, RouterLine.appleFM) }
        if let endpoint = route.endpoint {
            let name = "\(endpoint.name) · \(endpoint.model)"
            return (name, name)
        }
        guard let name = route.family?.name ?? route.copilotModel?.name else { return nil }
        guard let effort = route.effort else { return (name, name) }
        let level = String(localized: effort.label)
        return (String(localized: "\(name) · \(level)",
                       comment: "Model and effort in the reason line, such as «Sonnet 5.5 · medio»."),
                String(localized: "\(name), sforzo \(level)",
                       comment: "Model and effort in the reason line, as VoiceOver reads it: «Sonnet 5.5, sforzo medio»."))
    }
}

#Preview {
    VStack(alignment: .leading, spacing: Spacing.small) {
        RouterChip(route: Route(family: .sonnet, model: "sonnet", effort: .medium, reason: .type(.writing, runnerUp: nil)))
        RouterChip(route: .onDevice(.shortFact, runnerUp: nil))
        RouterChip(route: Route(family: .opus, model: "opus", effort: .high, reason: .chosenByUser))
    }
    .padding()
    .background(Palette.ink)
}
