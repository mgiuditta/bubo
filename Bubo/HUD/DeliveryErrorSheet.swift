import SwiftUI

/// The foglio "Non si apre" of a Consegna (spec 24, Errori): one text for each case, nothing of the content shown.
struct DeliveryErrorSheet: View {
    let failure: DeliveryOpener.Failure
    /// This Mac's name, for "rifarla per «‹questa›»".
    let machine: String
    let close: () -> Void
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            Label("Non si apre", systemImage: "exclamationmark.triangle")
                .font(.headline)
                .foregroundStyle(Palette.danger)
                .accessibilityAddTraits(.isHeader)
            Text(Self.message(for: failure, machine: machine))
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                if failure == .unknownSender {
                    Button("Impostazioni › Consegne") {
                        SettingsTab.deliveries.select()
                        openSettings()
                        close()
                    }
                }
                Button("OK", action: close)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spacing.large)
        .frame(width: 460, alignment: .leading)
    }

    /// The text of `failure`, on the Mac named `machine`.
    static func message(for failure: DeliveryOpener.Failure, machine: String) -> String {
        switch failure {
        case let .otherMachine(other?, sender?):
            String(localized: "Questa Consegna è per un'altra Macchina. È cifrata per «\(other)». Aprila lì, oppure chiedi a \(sender) di rifarla per «\(machine)».")
        case let .otherMachine(other?, nil):
            String(localized: "Questa Consegna è per un'altra Macchina. È cifrata per «\(other)». Aprila lì, oppure chiedi a chi l'ha mandata di rifarla per «\(machine)».")
        case let .otherMachine(nil, sender?):
            String(localized: "Questa Consegna è per un'altra Macchina. Aprila lì, oppure chiedi a \(sender) di rifarla per «\(machine)».")
        case .otherMachine(nil, nil):
            String(localized: "Questa Consegna è per un'altra Macchina. Aprila lì, oppure chiedi a chi l'ha mandata di rifarla per «\(machine)».")
        case let .damaged(sender?):
            String(localized: "Il file è stato modificato o è danneggiato. Bubo non lo apre. Chiedi a \(sender) di rimandarlo.")
        case .damaged(nil):
            String(localized: "Il file è stato modificato o è danneggiato. Bubo non lo apre. Chiedi a chi l'ha mandato di rimandarlo.")
        case .unknownSender:
            String(localized: "Non conosci chi l'ha mandata. Bubo apre solo Consegne di chi ha un Biglietto verificato. Scambiatevi i Biglietti, poi riaprila.")
        case let .baseUnreachable(sender, branch?):
            String(localized: "Il ramo parte da commit che non hai. Chiedi a \(sender) di pushare \(branch).")
        case let .baseUnreachable(sender, nil):
            String(localized: "Il ramo parte da commit che non hai. Chiedi a \(sender) di pushare il suo ramo.")
        case .unavailable:
            String(localized: "La chiave di questo Mac non si apre, o Bubo non riesce a scrivere la Consegna. Sblocca il Mac e riaprila.")
        }
    }
}
