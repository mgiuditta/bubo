#if DEBUG
import SwiftUI

/// The empty cell of a Variante the elenco plans but nobody has drawn yet: its name, and its silhouette on hover.
struct GalleriaPlaceholder: View {
    let voce: CatalogoElenco.Voce

    var body: some View {
        Text(verbatim: voce.nome)
            .font(.caption2)
            .foregroundStyle(Palette.textSecondary)
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .minimumScaleFactor(0.8)
            .padding(Spacing.xxSmall)
            .frame(width: 64, height: 64)
            .background {
                RoundedRectangle(cornerRadius: CornerRadius.small)
                    .strokeBorder(Palette.line, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            .contentShape(.rect)
            .help(voce.silhouette)
    }
}
#endif
