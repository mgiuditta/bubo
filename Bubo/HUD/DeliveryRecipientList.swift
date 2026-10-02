import SwiftUI
import UniformTypeIdentifiers

/// A chi, the left column of the foglio di Consegna: the Biglietti received as "Persona · Macchina" rows, the
/// verified ones to choose, those with a changed key shown but not chosen; then "+ Aggiungi con un Biglietto…".
struct DeliveryRecipientList: View {
    let tickets: [ReceivedTicket]
    let recipient: ReceivedTicket.ID?
    let choose: (ReceivedTicket) -> Void
    /// Opens a Biglietto chosen in the file panel.
    let addTicket: (URL) -> Void
    @Environment(\.openSettings) private var openSettings
    @State private var isImporting = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Text("A chi")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text("Si consegna a una Macchina, non a una persona.")
                .font(.caption)
                .foregroundStyle(Palette.textSecondary)
            if tickets.isEmpty {
                Text("Nessun Biglietto ricevuto. Fatti mandare il Biglietto del Mac a cui consegnare.")
                    .font(.callout)
                    .foregroundStyle(Palette.textSecondary)
            }
            ForEach(tickets) { ticket in
                row(for: ticket)
            }
            Button("Aggiungi con un Biglietto…", systemImage: "plus") { isImporting = true }
                .buttonStyle(.borderless)
                .fileImporter(isPresented: $isImporting, allowedContentTypes: [.buboFile]) { result in
                    if case let .success(url) = result { addTicket(url) }
                }
        }
    }

    @ViewBuilder
    private func row(for ticket: ReceivedTicket) -> some View {
        let isChosen = ticket.id == recipient
        if ticket.status == .verified {
            Button { choose(ticket) } label: {
                HStack(spacing: Spacing.xSmall) {
                    Image(systemName: isChosen ? "largecircle.fill.circle" : "circle")
                        .accessibilityHidden(true)
                    Text(verbatim: "\(ticket.person) · \(ticket.machine)")
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    TicketStatusChip(status: ticket.status)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isChosen ? .isSelected : [])
        } else {
            HStack(spacing: Spacing.xSmall) {
                Text(verbatim: "\(ticket.person) · \(ticket.machine)")
                    .lineLimit(1)
                    .foregroundStyle(Palette.textSecondary)
                Spacer(minLength: 0)
                TicketStatusChip(status: ticket.status)
                Button("Impostazioni…") { openSettings() }
                    .controlSize(.small)
                    .help("Confronta il nuovo codice in Impostazioni › Consegne")
            }
            .accessibilityElement(children: .combine)
            .accessibilityHint(Text("Non si sceglie finché non confrontate il nuovo codice in Impostazioni › Consegne."))
        }
    }
}
