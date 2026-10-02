import SwiftUI

/// The notice of a Sessione whose `claude` is over 2 GB (spec 25), with Riavvia when the turn can start again.
struct HeavySessionBanner: View {
    /// Interrupts the turn and asks its prompt again in a new `claude`; `nil` shows only the notice.
    let restart: (() -> Void)?

    var body: some View {
        HStack(spacing: Spacing.xSmall) {
            Label("Sessione pesante", systemImage: "memorychip")
                .font(Typography.mono(size: 11))
                .foregroundStyle(Palette.textPrimary)
                .help(restart == nil
                    ? Text("Claude usa più di 2 GB di memoria. Torna leggero alla fine del turno.")
                    : Text("Claude usa più di 2 GB di memoria. Riavvia interrompe il turno e ripete la richiesta con un Claude nuovo, nella stessa copia."))
            if let restart {
                Button("Riavvia", action: restart)
                    .controlSize(.small)
            }
        }
    }
}

#Preview {
    VStack(alignment: .leading) {
        HeavySessionBanner {}
        HeavySessionBanner(restart: nil)
    }
    .padding()
    .background(Palette.ink)
}
