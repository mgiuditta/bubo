import SwiftUI

/// Impostazioni › Consegne: this Mac's Biglietto to share, and the Biglietti received with their code (spec 24).
struct DeliveriesSettingsView: View {
    @Environment(DeliveriesController.self) private var deliveries

    var body: some View {
        @Bindable var deliveries = deliveries
        Form {
            Section("Il mio Biglietto") {
                LabeledContent("Macchina", value: deliveries.machine)
                TextField("Nome", text: $deliveries.person)
                Text("Chiave nel Secure Enclave di questo Mac, non si esporta. Manda il Biglietto a chi deve consegnarti Sessioni, poi confrontate il codice a voce.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let file = deliveries.ownTicketFile {
                    ShareLink("Condividi…", item: file)
                }
            }
            Section("Biglietti ricevuti") {
                if deliveries.tickets.isEmpty {
                    Text("Nessun Biglietto. Apri quello che ti mandano per aggiungerlo.")
                        .foregroundStyle(.secondary)
                }
                ForEach(deliveries.tickets) { ticket in
                    ReceivedTicketRow(ticket: ticket, deliveries: deliveries)
                }
            }
            if let failure = deliveries.failure {
                Section {
                    Text(failure)
                        .foregroundStyle(Palette.danger)
                }
            }
        }
        .formStyle(.grouped)
        .task { await deliveries.load() }
    }
}

/// A Biglietto received: Persona · Macchina, its code and its state, with Rimuovi and, for a changed key, Riverifica.
private struct ReceivedTicketRow: View {
    let ticket: ReceivedTicket
    let deliveries: DeliveriesController
    @State private var isConfirmingRemoval = false

    var body: some View {
        LabeledContent {
            HStack {
                if ticket.status == .keyChanged, ticket.replacement != nil {
                    Button("Riverifica") { deliveries.reverify(ticket) }
                }
                Button("Rimuovi", role: .destructive) { isConfirmingRemoval = true }
                    .confirmationDialog("Rimuovere il Biglietto di «\(ticket.person)»?", isPresented: $isConfirmingRemoval) {
                        Button("Rimuovi", role: .destructive) { deliveries.remove(ticket) }
                    } message: {
                        Text("Non potrai più consegnare a «\(ticket.machine)» né aprire le sue Consegne, finché non vi scambiate di nuovo i Biglietti.")
                    }
            }
        } label: {
            HStack(spacing: Spacing.xSmall) {
                Text(verbatim: "\(ticket.person) · \(ticket.machine)")
                TicketStatusChip(status: ticket.status)
            }
            if let code = deliveries.code(of: ticket) {
                VerificationCodeText(code: code)
                    .font(.system(.callout, design: .monospaced))
            }
        }
    }
}
