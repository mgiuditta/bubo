import SwiftUI

/// The Quota at the top of the HUD: the 5-hour and the weekly window, each with its reset, with no click.
///
/// A window `claude` never reported, or whose reset has passed, is not shown: Bubo never guesses it. A click opens
/// the Costi window (spec 18).
struct QuotaView: View {
    let quota: Quota
    /// Opens the Costi window.
    var showCosts: () -> Void = {}

    var body: some View {
        Button(action: showCosts) { windows }
            .buttonStyle(.plain)
            .help("Apri i Costi")
            .accessibilityHint(Text("Apre la finestra Costi"))
            // With no window reported there is nothing to read; the Finestra menu still opens the Costi.
            .accessibilityHidden(quota.fiveHour == nil && quota.sevenDay == nil)
    }

    private var windows: some View {
        TimelineView(.everyMinute) { context in
            HStack(spacing: Spacing.medium) {
                if let window = quota.fiveHour, window.resetsAt > context.date {
                    QuotaWindowLabel(title: "5 ore", used: window.used,
                                     reset: "si azzera alle \(window.resetsAt, format: .dateTime.hour().minute())")
                }
                if let window = quota.sevenDay, window.resetsAt > context.date {
                    QuotaWindowLabel(title: "Settimana", used: window.used,
                                     reset: "si azzera \(window.resetsAt, format: .dateTime.weekday(.abbreviated)) alle \(window.resetsAt, format: .dateTime.hour().minute())")
                }
            }
        }
    }
}

/// One Quota window: its name, the share used and when it resets.
private struct QuotaWindowLabel: View {
    let title: LocalizedStringKey
    let used: Double
    let reset: LocalizedStringKey

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(spacing: Spacing.xSmall) {
                Text(title)
                    .textCase(.uppercase)
                    .foregroundStyle(Palette.textSecondary)
                Text(used, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: used))
                    .animation(Motion.isReduced ? nil : Motion.standard, value: used)
            }
            .font(Typography.mono(size: 11, weight: .medium))
            Text(reset)
                .font(Typography.mono(size: 10))
                .foregroundStyle(Palette.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Quota \(Text(title)): \(used, format: .percent.precision(.fractionLength(0))) usata"))
        .accessibilityValue(Text(reset))
    }
}

#Preview {
    QuotaView(quota: Quota(fiveHour: Quota.Window(used: 0.2, resetsAt: .now.addingTimeInterval(3_600)),
                           sevenDay: Quota.Window(used: 0.02, resetsAt: .now.addingTimeInterval(500_000))))
        .padding()
        .background(Palette.ink)
}
