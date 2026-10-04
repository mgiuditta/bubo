import SwiftUI

/// What Bubo shows at a subscription limit: the cause, the reset and three choices (ADR 0003).
///
/// None of the choices starts on its own; the API key also asks for a confirmation, because it is paid per use.
struct LimitNotice: View {
    let limit: Quota.Limit
    /// Waits for the reset, then asks again; offered only when the reset is known.
    let resume: () -> Void
    /// Asks again with `limit.otherModel`.
    let switchModel: () -> Void
    /// Asks again with the API key; runs only after the user confirms.
    let useAPIKey: () -> Void

    @State private var isConfirmingAPIKey = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
                Image(systemName: "hourglass")
                    .foregroundStyle(Palette.textSecondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                    Text(cause)
                        .font(Typography.body(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                    reset
                        .font(Typography.body(size: 13))
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            HStack(spacing: Spacing.xSmall) {
                if limit.resetsAt != nil {
                    Button("Riprendi dopo il reset", action: resume)
                }
                Button("Riprova con \(limit.otherModel.capitalized)", action: switchModel)
                Button("Usa la API key…") { isConfirmingAPIKey = true }
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
        .confirmationDialog("Vuoi passare alla API key?", isPresented: $isConfirmingAPIKey) {
            Button("Usa la API key", action: useAPIKey)
        } message: {
            Text("Domande e Sessioni si pagano a consumo con la tua API key finché non chiudi Bubo.")
        }
    }

    private var cause: LocalizedStringKey {
        switch limit.window {
        case "five_hour": "Hai raggiunto il limite delle 5 ore"
        case "seven_day": "Hai raggiunto il limite settimanale"
        case "seven_day_opus": "Hai raggiunto il limite settimanale di Opus"
        case "seven_day_sonnet": "Hai raggiunto il limite settimanale di Sonnet"
        default: "Hai raggiunto il limite dell'abbonamento"
        }
    }

    private var reset: Text {
        guard let resetsAt = limit.resetsAt else { return Text("Claude non ha detto quando si azzera.") }
        let time = resetsAt.formatted(date: .omitted, time: .shortened)
        return Calendar.current.isDateInToday(resetsAt)
            ? Text("Si azzera alle \(time).")
            : Text("Si azzera \(resetsAt, format: .dateTime.weekday(.wide)) alle \(time).")
    }
}

#Preview {
    VStack {
        LimitNotice(limit: Quota.Limit(window: "five_hour", resetsAt: .now.addingTimeInterval(3_600)),
                    resume: {}, switchModel: {}, useAPIKey: {})
        LimitNotice(limit: Quota.Limit(window: "seven_day_sonnet", resetsAt: .now.addingTimeInterval(300_000)),
                    resume: {}, switchModel: {}, useAPIKey: {})
        LimitNotice(limit: Quota.Limit(), resume: {}, switchModel: {}, useAPIKey: {})
    }
    .padding()
    .background(Palette.ink)
}
