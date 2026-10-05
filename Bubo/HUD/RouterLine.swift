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
            Text(Self.reason(for: answer.route))
                .foregroundStyle(Palette.textSecondary)
                .truncationMode(.tail)
                .layoutPriority(-1)
            Spacer(minLength: Spacing.xSmall)
            if let budget = answer.budgetNotice {
                Text(Self.text(of: budget))
                    .foregroundStyle(Palette.attention)
                    .accessibilityIdentifier("question.budgetNotice")
            }
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
        if let copilot = answer.route.copilotModel {
            // The name `listModels()` gives, not `copilot`'s id; for the model set in `copilot`, the one it answered with.
            let answering = copilot == .configured ? answer.answeringModel?.name : nil
            (name, effort) = (answering ?? copilot.name, answer.answeringModel?.effort ?? answer.route.effort)
        } else if let answering = answer.answeringModel {
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
    static let appleFM = "Apple FM"

    /// Why the router chose `route`, as the line and the chip in the prompt say it.
    static func reason(for route: Route) -> LocalizedStringResource {
        switch route.exhaustedEngine {
        case .claude?:
            return LocalizedStringResource("Quota di Claude finita: risponde Copilot",
                                           comment: "Reason line: Claude's Quota ran out or hit a limit, so Copilot, the Riserva, answers this Domanda.")
        case .copilot?:
            return LocalizedStringResource("Quota di Copilot finita: risponde Claude",
                                           comment: "Reason line: Copilot's Quota ran out or hit a limit, so Claude, the Riserva, answers this Domanda.")
        case nil:
            break
        }
        let family = switch route.destination {
        case .claude: route.family?.name ?? ""
        case .onDevice: appleFM
        case let .endpoint(endpoint): endpoint.name
        case let .copilot(model): model.name
        }
        if route.copilotModel != nil {
            // Copilot is a channel, not the model's vendor: the line says it (ADR 0011).
            let reason = String(localized: reason(for: route, named: family))
            return LocalizedStringResource("\(reason), via Copilot",
                                           comment: "Reason line of an answer from a model of the user's GitHub Copilot plan: the reason, then «via Copilot».")
        }
        return reason(for: route, named: family)
    }

    /// Why the router chose `route`, whose model is called `family`.
    private static func reason(for route: Route, named family: String) -> LocalizedStringResource {
        if case let .type(type, _) = route.reason, let avoided = route.avoidedBudget {
            let budget = BudgetGuard.Scope.provider(avoided).budgetTitle
            return LocalizedStringResource("\(String(localized: type.label)) → \(family), \(budget) oltre la soglia",
                                           comment: Self.comment)
        }
        if case let .type(type, _) = route.reason, let pause = route.pausedPreference {
            return reason(String(localized: type.label), family, pause)
        }
        if case let .type(type, _) = route.reason, let fallback = route.onDeviceFallback {
            return reason(String(localized: type.label), family, fallback)
        }
        switch route.reason {
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
        case let .preferred(type):
            return LocalizedStringResource("\(String(localized: type.label)) → \(family) (tua preferenza)",
                                           comment: Self.comment)
        case let .offline(type):
            return LocalizedStringResource("\(String(localized: type.label)) → \(family), senza rete",
                                           comment: Self.comment)
        case let .quota(type, threshold):
            let percent = threshold.formatted(.percent.precision(.fractionLength(0)))
            return LocalizedStringResource(
                "\(String(localized: type.label)) → \(family), quota di 5 ore oltre la soglia (\(percent))",
                comment: Self.comment)
        }
    }

    /// Why a Tipo with a preference went to its default, `family`, instead.
    private static func reason(_ type: String, _ family: String,
                               _ pause: Route.PausedPreference) -> LocalizedStringResource {
        switch pause {
        case let .notInCatalog(preferred):
            LocalizedStringResource("\(type) → \(family), tua preferenza \(preferred.name) non disponibile",
                                    comment: comment)
        case .endpointUnavailable:
            LocalizedStringResource("\(type) → \(family), tua preferenza in pausa", comment: comment)
        case .attachments:
            LocalizedStringResource("\(type) → \(family), gli allegati vanno solo a Claude o sul Mac", comment: comment)
        case let .localServerOff(server):
            LocalizedStringResource("\(type) → \(family), \(server) non risponde", comment: comment)
        case let .localModelMissing(server):
            LocalizedStringResource("\(type) → \(family), \(server) non ha più il modello", comment: comment)
        case let .overBudget(provider):
            LocalizedStringResource(
                "\(type) → \(family), tua preferenza in pausa: \(BudgetGuard.Scope.provider(provider).budgetTitle) oltre la soglia",
                comment: comment)
        }
    }

    /// Why a Tipo that Apple Foundation Models answers went to `family` instead.
    private static func reason(_ type: String, _ family: String,
                               _ fallback: Route.OnDeviceFallback) -> LocalizedStringResource {
        switch fallback {
        case .attachmentTooLong:
            LocalizedStringResource("\(type) → \(family), allegato troppo lungo per Apple FM", comment: comment)
        case .attachmentNotText:
            LocalizedStringResource("\(type) → \(family), allegato che Apple FM non legge", comment: comment)
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

    /// What the line says of the Budgets after the turn.
    static func text(of notice: BudgetNotice) -> LocalizedStringResource {
        switch notice {
        case let .reached(scope, share) where share >= 1:
            LocalizedStringResource("\(scope.budgetTitle) esaurito",
                                    comment: "Reason line: the monthly Budget the answer counts in is spent, such as «Budget di OpenAI esaurito».")
        case let .reached(scope, share):
            LocalizedStringResource("\(scope.budgetTitle): \(share.formatted(.percent.precision(.fractionLength(0))))",
                                    comment: "Reason line: the monthly Budget the answer counts in is past its threshold, with the share spent, such as «Budget di OpenAI: 84%».")
        case .unpriced:
            LocalizedStringResource("senza prezzo, fuori dal Budget",
                                    comment: "Reason line: the model has no known price, so its provider's Budget cannot count the answer.")
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
        case let .copilotEstimate(value, _)?:
            let credits = (value * 100).formatted(.number.precision(.fractionLength(0...1)))
            let dollars = SessionCostTotal.formatted(value)
            if credits == 1.formatted() {
                return String(localized: "stima: 1 credito Copilot, \(dollars)",
                              comment: "Cost of an answer from GitHub Copilot, estimated from its tokens on GitHub's list prices: one AI credit, then the same in dollars.")
            }
            return String(localized: "stima: \(credits) crediti Copilot, \(dollars)",
                          comment: "Cost of an answer from GitHub Copilot, estimated from its tokens on GitHub's list prices: the AI credits, then the same in dollars (a credit is a cent).")
        case let .copilotTokens(count)?:
            return String(localized: "\(count.formatted()) token Copilot, senza prezzo",
                          comment: "Cost of an answer from GitHub Copilot on a model missing from Bubo's list of GitHub's prices: the tokens used.")
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
        case let .copilotEstimate(_, date)?:
            return LocalizedStringResource("Stima: token contati da Copilot, sul listino GitHub del \(date.formatted(date: .long, time: .omitted)), 1 credito = $0,01. Bubo non vede i crediti scalati dal tuo account.")
        case .copilotTokens?:
            return LocalizedStringResource("Token contati da Copilot. Il modello non è nel listino GitHub di Bubo, quindi la cifra manca.")
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
        RouterLine(answer: RoutedAnswer(route: Route(family: .opus, model: "opus", effort: .high,
                                                     reason: .preferred(.writing)), provider: .anthropic))
        RouterLine(answer: RoutedAnswer(route: Route(family: .sonnet, model: "sonnet", effort: .medium,
                                                     reason: .type(.writing, runnerUp: nil),
                                                     pausedPreference: .notInCatalog(.fable)), provider: .anthropic))
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
