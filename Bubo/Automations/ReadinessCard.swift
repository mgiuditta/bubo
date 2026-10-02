import SwiftUI

/// The two optional switches that keep the Automazioni ready without a daemon, both off until the user turns them on:
/// "Apri Bubo al login" and "Tieni sveglio il Mac" (spec 19).
struct ReadinessCard: View {
    @AppStorage(KeepAwake.defaultsKey) private var keepsMacAwake = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Text("Le Automazioni partono solo con Bubo aperto e il Mac sveglio.")
                .font(Typography.body(size: 12, weight: .semibold))
            LoginItemToggle()
            Toggle("Tieni sveglio il Mac quando c'è un'Automazione nelle prossime 2 ore", isOn: $keepsMacAwake)
                .tint(Palette.switchTrack)
            Text("Con il coperchio chiuso il Mac dorme comunque.")
                .font(Typography.body(size: 11))
                .foregroundStyle(Palette.textSecondary)
        }
        .font(Typography.body(size: 12))
        .padding(Spacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: .rect(cornerRadius: CornerRadius.large))
    }
}

#Preview {
    ReadinessCard()
        .padding()
        .background(Palette.ink)
}
