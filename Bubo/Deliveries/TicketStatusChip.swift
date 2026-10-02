import SwiftUI

/// The state of a Biglietto received: `verificato`, or `chiave cambiata`. A word and a symbol, not only a colour.
struct TicketStatusChip: View {
    let status: ReceivedTicket.Status

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: status == .verified ? "checkmark.seal" : "exclamationmark.triangle")
        }
        .labelStyle(.titleAndIcon)
        .font(.caption)
        .foregroundStyle(status == .verified ? Palette.success : Palette.danger)
        .padding(.horizontal, Spacing.xSmall)
        .padding(.vertical, Spacing.xxSmall / 2)
        .overlay { Capsule().strokeBorder(Palette.line) }
    }

    private var title: LocalizedStringKey {
        status == .verified ? "verificato" : "chiave cambiata"
    }
}
