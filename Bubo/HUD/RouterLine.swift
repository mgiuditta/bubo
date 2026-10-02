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

    /// Apple Foundation Models as the line names it; a brand, so it is never translated.
    private static let appleFM = "Apple FM"

    private var reason: LocalizedStringResource {
        let family = answer.route.destination == .onDevice ? Self.appleFM : answer.route.family?.name ?? ""
        if case let .type(type, _) = answer.route.reason, let fallback = answer.route.onDeviceFallback {
            return Self.reason(String(localized: type.label), family, fallback)
        }
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
        case .retried:
            return LocalizedStringResource("Rifatto da te", comment: Self.comment)
        }
    }

    /// Why a Tipo that Apple Foundation Models answers went to `family` instead.
    private static func reason(_ type: String, _ family: String,
                               _ fallback: Route.OnDeviceFallback) -> LocalizedStringResource {
        switch fallback {
        case .attachmentTooLong:
            LocalizedStringResource("\(type) → \(family), allegato troppo lungo per Apple FM", comment: comment)
        case .questionTooLong:
            LocalizedStringResource("\(type) → \(family), domanda troppo lunga per Apple FM", comment: comment)
        case .attachmentNotMeasurable:
            LocalizedStringResource("\(type) → \(family), Apple FM con allegati richiede macOS 26.4", comment: comment)
        case .unavailable:
            LocalizedStringResource("\(type) → \(family), Apple Intelligence non disponibile: solo regole",
                                    comment: comment)
        case .failed:
            LocalizedStringResource("\(type) → \(family), Apple FM non ha risposto", comment: comment)
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
        case let .estimate(value, date)?:
            let estimate = String(localized: "circa \(SessionCostTotal.formatted(value)) sulla tua chiave",
                                  comment: "Cost of an answer from another provider, paid on the user's own key: tokens times the provider's list prices.")
            // Prices older than 30 days say which day they are from.
            guard Date.now.timeIntervalSince(date) > 30 * 24 * 60 * 60 else { return estimate }
            return String(localized: "\(estimate) · prezzi del \(date.formatted(.dateTime.day().month(.wide)))",
                          comment: "Cost of an answer, then the day of the price table it was estimated with, such as «prezzi del 12 agosto».")
        case .free?:
            return String(localized: "gratis, sul Mac", comment: "Cost of an answer from a model running on this Mac.")
        case let .tokens(count)?:
            return String(localized: "\(count.formatted()) token sulla tua chiave",
                          comment: "Cost of an answer from another provider, paid on the user's own key at a price Bubo does not know: the tokens used.")
        case nil:
            return nil
        }
    }

    /// Where the cost comes from: `claude`'s own window for a share, the SDK's estimate for a figure.
    private var costOrigin: LocalizedStringResource {
        switch answer.cost {
        case .fiveHourShare?:
            return LocalizedStringResource("Quota di 5 ore usata durante la risposta, come la riporta Claude.")
        case .free?:
            return LocalizedStringResource("Il modello gira su questo Mac: la Domanda non lo lascia.")
        case .tokens?:
            return LocalizedStringResource("Token contati dal fornitore, che li addebita sulla tua chiave. Bubo non conosce il prezzo.")
        case let .estimate(_, date)?:
            return LocalizedStringResource("Token contati dal fornitore per i prezzi di models.dev del \(date.formatted(date: .long, time: .omitted)): una stima, non una fattura.")
        case .spesa? where answer.endpoint != nil:
            return LocalizedStringResource("Cifra riportata dal fornitore nella risposta.")
        default:
            break
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
        RouterLine(answer: RoutedAnswer(route: .onDevice(.shortFact, runnerUp: nil), provider: nil))
        RouterLine(answer: RoutedAnswer(route: Route(family: .haiku, model: "haiku", effort: nil,
                                                     reason: .type(.summary, runnerUp: nil),
                                                     onDeviceFallback: .attachmentTooLong), provider: .anthropic))
        RouterLine(answer: RoutedAnswer(route: .chosen("sonnet"), provider: .anthropic))
        RouterLine(answer: RoutedAnswer(route: .stronger(Scala.Step(family: .opus, effort: .high)), provider: .anthropic))
        RouterLine(answer: {
            var endpoint = OpenAICompatibleEndpoint.known[0]
            endpoint.model = "gpt-5-mini"
            var answer = RoutedAnswer(route: .retriedElsewhere, provider: .openAI, endpoint: endpoint)
            answer.answeringModel = AnsweringModel(model: endpoint.model, effort: nil)
            answer.endpointTokens = 1_234
            return answer
        }())
        RouterLine(answer: {
            var endpoint = OpenAICompatibleEndpoint.known[0]
            endpoint.model = "gpt-5-mini"
            var answer = RoutedAnswer(route: .retriedElsewhere, provider: .openAI, endpoint: endpoint)
            answer.answeringModel = AnsweringModel(model: endpoint.model, effort: nil)
            answer.usage = TurnUsage(mode: .apiKey, cost: 0.0042, basis: .list, isComplete: true, models: [],
                                     origin: .priceTable, priceDate: .now.addingTimeInterval(-45 * 24 * 60 * 60))
            return answer
        }())
    }
    .frame(width: 560)
    .padding()
    .background(Palette.ink)
}
