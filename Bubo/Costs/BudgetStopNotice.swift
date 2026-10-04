import SwiftUI

/// What Bubo shows when a Budget is spent and a Domanda or a Sessione stops (spec 18): never a block without a way
/// out, and nothing starts again without the user's choice.
///
/// Going past the Budget asks for a confirmation; the other choices stay within it.
struct BudgetStopNotice: View {
    /// The Budget spent.
    let scope: BudgetGuard.Scope
    /// What stopped, and how it starts again.
    let detail: LocalizedStringKey
    /// Asks again within the Budgets, once raised.
    let retry: () -> Void
    /// Asks again past the Budget, this time only; runs only after the user confirms.
    let continueOnce: () -> Void
    /// Asks again with the subscription, where it makes sense: Claude with the API key (ADR 0003).
    var switchToSubscription: (() -> Void)?
    /// Asks again with the Modello locale, where it makes sense: a Domanda, with one set.
    var switchToLocalModel: (() -> Void)?

    @Environment(\.openSettings) private var openSettings
    @State private var isConfirming = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
                Image(systemName: "gauge.with.dots.needle.100percent")
                    .foregroundStyle(Palette.attention)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                    Text(RouterLine.text(of: .reached(scope, share: 1)))
                        .font(Typography.body(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                    Text(detail)
                        .font(Typography.body(size: 13))
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            HStack(spacing: Spacing.xSmall) {
                Button("Aumenta il Budget…") {
                    SettingsTab.budget.select()
                    openSettings()
                }
                Button("Riprova", action: retry)
                Button("Continua solo questa volta…") { isConfirming = true }
            }
            if switchToSubscription != nil || switchToLocalModel != nil {
                HStack(spacing: Spacing.xSmall) {
                    if let switchToSubscription {
                        Button("Passa all'abbonamento", action: switchToSubscription)
                    }
                    if let switchToLocalModel {
                        Button("Passa al locale", action: switchToLocalModel)
                    }
                }
            }
        }
        .padding(Spacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: .rect(cornerRadius: CornerRadius.large))
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.large)
                .strokeBorder(Palette.lineStrong)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("budget.stop")
        .confirmationDialog("Vuoi andare oltre il Budget?", isPresented: $isConfirming) {
            Button("Continua solo questa volta", action: continueOnce)
        } message: {
            Text("Solo questa volta si spende oltre il limite. Per i turni dopo il Budget resta com'è.")
        }
    }
}

#Preview {
    VStack {
        BudgetStopNotice(scope: .provider(Budgets.claude), detail: "La Sessione si è fermata: riparte solo con una tua scelta.",
                         retry: {}, continueOnce: {}, switchToSubscription: {})
        BudgetStopNotice(scope: .provider("OpenAI"), detail: "Bubo non manda la Domanda senza una tua scelta.",
                         retry: {}, continueOnce: {}, switchToLocalModel: {})
    }
    .padding()
    .background(Palette.ink)
}
