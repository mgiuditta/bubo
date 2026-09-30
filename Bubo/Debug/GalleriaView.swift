#if DEBUG
import SwiftUI

/// The Galleria del Catalogo: every Variante at 64 pt in greys, filtered by Categoria, and the chosen one large and live.
///
/// It checks each block of Forme: whether the silhouette reads at small size and the halo has no streaks.
/// Choosing a Variante asks the large Orb for it, so the change runs through the Regia del Morph.
struct GalleriaView: View {
    let catalogo: Catalogo

    /// Where the Snapshotter comes from; it lives as long as the app, like the Catalogo.
    private static let snapshotter = Result { try OrbSnapshotter() }

    @State private var categoria: Categoria?
    /// The large Orb's own controls: the Galleria never changes the Panel's Orb.
    @State private var controls = GalleriaView.makeControls()

    private var shown: [Variante] {
        categoria.map(catalogo.varianti(in:)) ?? catalogo.varianti
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Spacing.small) {
                Picker("Categoria", selection: $categoria) {
                    Text("Tutte").tag(Categoria?.none)
                    ForEach(Categoria.allCases, id: \.self) { categoria in
                        Text(verbatim: categoria.rawValue.capitalized).tag(Optional(categoria))
                    }
                }
                .fixedSize()
                .padding([.top, .horizontal], Spacing.medium)

                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 64, maximum: 64), spacing: Spacing.small)],
                              spacing: Spacing.small) {
                        ForEach(shown) { variante in
                            Button {
                                controls.variante = variante
                            } label: {
                                GalleriaThumbnail(variante: variante, snapshotter: try? Self.snapshotter.get())
                            }
                            .buttonStyle(.plain)
                            .overlay {
                                RoundedRectangle(cornerRadius: CornerRadius.small)
                                    .strokeBorder(Palette.lineStrong, lineWidth: 1)
                                    .opacity(controls.variante == variante ? 1 : 0)
                            }
                            .accessibilityLabel(Text(variante.label))
                            .accessibilityAddTraits(controls.variante == variante ? .isSelected : [])
                        }
                    }
                    .padding(Spacing.medium)
                }
            }
            .frame(minWidth: 320)

            GalleriaOrbView(controls: controls)
                .frame(width: 360, height: 360)
                .accessibilityElement()
                .accessibilityLabel(Text(controls.variante?.label ?? "Blob"))
        }
        .background(Palette.ink)
        .environment(\.colorScheme, .dark) // the halo reads only on the dark of the Notte direction
        .frame(minHeight: 400)
    }

    /// Controls held in Ascolto: in Riposo the Orb would go back to the Blob after 5 s.
    private static func makeControls() -> OrbControls {
        let controls = OrbControls()
        controls.state = .listening
        return controls
    }
}
#endif
