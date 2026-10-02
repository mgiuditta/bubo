import SwiftUI

/// The line under every answer (spec 10): the Tinta's dot, model · effective effort, the reason, the estimated cost.
struct RouterLine: View {
    let answer: RoutedAnswer

    var body: some View {
        HStack(spacing: Spacing.xSmall) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            if let model {
                Text(verbatim: model.text)
                    .foregroundStyle(Palette.textPrimary)
                    .accessibilityLabel(model.spoken)
            }
            Text(reason)
                .foregroundStyle(Palette.textSecondary)
                .truncationMode(.tail)
                .layoutPriority(-1)
            Spacer(minLength: Spacing.xSmall)
            if let cost {
                Text(verbatim: cost)
                    .font(Typography.mono(size: 11))
                    .foregroundStyle(Palette.textSecondary)
                    .help(Text(costOrigin))
            }
        }
        .font(Typography.body(size: 12))
        .lineLimit(1)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("question.routerLine")
    }

    /// The provider's Tinta, as the Orb wore it while answering.
    private var tint: Color {
        let base = Tinta(for: answer.provider).base
        return Color(.sRGB, red: Double(base.x), green: Double(base.y), blue: Double(base.z))
    }

    /// Who answered and with which effort, as read and as VoiceOver says it; until the bridge says, the family the
    /// router asked for.
    private var model: (text: String, spoken: String)? {
        let name: String
        let effort: Effort?
        if let answering = answer.answeringModel {
            (name, effort) = (answering.name, answering.effort)
        } else if let family = answer.route.family {
            (name, effort) = (family.name, answer.route.effort)
        } else {
            return nil
        }
        guard let effort else { return (name, name) }
        let level = String(localized: effort.label)
        return (String(localized: "\(name) · \(level)",
                       comment: "Model and effort in the reason line, such as «Sonnet 5.5 · medio»."),
                String(localized: "\(name), sforzo \(level)",
                       comment: "Model and effort in the reason line, as VoiceOver reads it: «Sonnet 5.5, sforzo medio»."))
    }

    private var reason: LocalizedStringResource {
        let family = answer.route.family?.name ?? ""
        switch answer.route.reason {
        case let .type(type, nil):
            return LocalizedStringResource("\(String(localized: type.label)) → \(family)", comment: Self.comment)
        case let .type(type, runnerUp?):
            return LocalizedStringResource(
                "\(String(localized: type.label)) o \(String(localized: runnerUp.label)) → \(family)",
                comment: Self.comment)
        case let .unavailable(type, unavailable):
            return LocalizedStringResource(
                "\(String(localized: type.label)) → modello predefinito, \(unavailable.name) non disponibile",
                comment: Self.comment)
        case .unclassified:
            return LocalizedStringResource("Richiesta non classificata → modello predefinito", comment: Self.comment)
        case .chosenByUser:
            return LocalizedStringResource("Scelto da te", comment: Self.comment)
        case .stronger:
            return LocalizedStringResource("Rifai più forte → \(family)", comment: Self.comment)
        }
    }

    private var cost: String? {
        switch answer.cost {
        case let .fiveHourShare(share)?:
            if share < 0.001 {
                return String(localized: "meno dello 0,1% della finestra di 5 ore",
                              comment: "Cost of an answer: under a thousandth of the subscription's 5-hour window.")
            }
            return String(localized: "\(share.formatted(.percent.precision(.fractionLength(0...1)))) della finestra di 5 ore",
                          comment: "Cost of an answer as a share of the subscription's 5-hour window.")
        case let .listValue(value)?:
            return String(localized: "\(SessionCostTotal.formatted(value)) a listino",
                          comment: "Cost of an answer at list price, included in the subscription.")
        case let .spesa(value)?:
            return String(localized: "Spesa: \(SessionCostTotal.formatted(value))",
                          comment: "Cost of an answer paid with the API key.")
        case nil:
            return nil
        }
    }

    /// Where the cost comes from: `claude`'s own window for a share, the SDK's estimate for a figure.
    private var costOrigin: LocalizedStringResource {
        if case .fiveHourShare = answer.cost {
            return LocalizedStringResource("Quota di 5 ore usata durante la risposta, come la riporta Claude.")
        }
        return LocalizedStringResource("Stima calcolata sul Mac: non è una fattura.")
    }

    private static let comment: StaticString = """
        Reason line under an answer: why the router chose the model. The Tipo di richiesta, then an arrow and the \
        model family (a brand, never translated).
        """
}

#Preview {
    VStack(alignment: .leading, spacing: Spacing.small) {
        RouterLine(answer: {
            var answer = RoutedAnswer(route: Route(family: .sonnet, model: "sonnet", effort: .medium,
                                                   reason: .type(.writing, runnerUp: nil)), provider: .anthropic)
            answer.answeringModel = AnsweringModel(model: "claude-sonnet-5-5", effort: .medium)
            answer.fiveHourShare = 0.012
            return answer
        }())
        RouterLine(answer: RoutedAnswer(route: Route(family: .opus, model: "opus", effort: .medium,
                                                     reason: .type(.reasoning, runnerUp: .writing)), provider: .anthropic))
        RouterLine(answer: RoutedAnswer(route: .chosen("sonnet"), provider: .anthropic))
        RouterLine(answer: RoutedAnswer(route: .stronger(Scala.Step(family: .opus, effort: .high)), provider: .anthropic))
    }
    .frame(width: 560)
    .padding()
    .background(Palette.ink)
}
