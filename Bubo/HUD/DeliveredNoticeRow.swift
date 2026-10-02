import SwiftUI

/// The notice on a Sessione's card after a Consegna: "Consegnata con ‹canale› a ‹nome›…", with Chiudi. No receipt
/// follows (spec 24).
struct DeliveredNoticeRow: View {
    let notice: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xSmall) {
            Text(verbatim: notice)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Chiudi", systemImage: "xmark", action: dismiss)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        }
        .font(Typography.body(size: 12))
        .foregroundStyle(Palette.textSecondary)
    }
}
