#if DEBUG
import SwiftUI

/// What the elenco planned for the chosen Variante, under the large Orb, to hold the Forma up against it.
struct GalleriaVoceDetail: View {
    let cell: GalleriaCell

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Text(verbatim: cell.nome)
                .font(.headline)
                .foregroundStyle(Palette.textPrimary)
            if cell.isToDraw {
                Text("Da disegnare")
                    .foregroundStyle(Palette.attention)
            }
            if let voce = cell.voce {
                Text(verbatim: voce.descrizione)
                Text("Silhouette: \(voce.silhouette)")
                if let moto = voce.moto {
                    Text("Moto: \(moto)")
                }
            }
        }
        .font(.callout)
        .foregroundStyle(Palette.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.medium)
    }
}
#endif
