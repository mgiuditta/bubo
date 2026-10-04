import DeliveryKit
import SwiftUI

/// A Biglietto opened with a double click, or Riverifica: the code in large to compare aloud, then Non coincide ·
/// Coincide; after Coincide, "Manda il mio Biglietto…" (spec 24, Biglietto). A changed key has the warning on top.
struct TicketImportSheet: View {
    let pending: DeliveriesController.TicketImport
    let deliveries: DeliveriesController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            switch pending.review {
            case .own:
                Text("È il Biglietto di questo Mac. Mandalo a chi deve consegnarti Sessioni.")
                footer { doneButton }
            case .alreadyVerified:
                Text("Il Biglietto di \(person) per «\(machine)» è già verificato.")
                footer { doneButton }
            case .new, .keyChanged:
                if pending.isConfirmed {
                    confirmed
                } else {
                    comparison
                }
            }
        }
        .padding(Spacing.large)
        .frame(width: 460, alignment: .leading)
    }

    private var person: String { pending.ticket.person }
    private var machine: String { pending.ticket.machine }

    private var comparison: some View {
        Group {
            if case .keyChanged = pending.review {
                Label {
                    Text("La chiave di \(person) è cambiata. Può essere un Mac reinstallato, o qualcuno che si spaccia per \(person). Finché non confrontate il codice, non puoi consegnare lì.")
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .foregroundStyle(Palette.danger)
            }
            Text("Biglietto di \(person) per «\(machine)»")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            VerificationCodeText(code: pending.code)
                .font(.system(.largeTitle, design: .monospaced))
                .frame(maxWidth: .infinity)
            Text("Leggetevi il codice a voce o in chiamata. Deve essere uguale sul Mac di \(person).")
                .foregroundStyle(.secondary)
            footer {
                Button("Non coincide", role: .destructive) {
                    deliveries.reject()
                    dismiss()
                }
                Button("Coincide") { deliveries.confirm() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var confirmed: some View {
        Group {
            Label("Biglietto di \(person) verificato.", systemImage: "checkmark.seal")
                .font(.headline)
            Text("Ora manda il tuo: senza il tuo Biglietto, \(person) non può aprire le tue Consegne né mandartene.")
                .foregroundStyle(.secondary)
            footer {
                Button("Non ora") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                if let file = deliveries.ownTicketFile {
                    ShareLink("Manda il mio Biglietto…", item: file)
                }
            }
        }
    }

    private var doneButton: some View {
        Button("OK") { dismiss() }
            .keyboardShortcut(.defaultAction)
    }

    private func footer(@ViewBuilder _ buttons: () -> some View) -> some View {
        HStack {
            Spacer()
            buttons()
        }
    }
}
