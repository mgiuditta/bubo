#if DEBUG
import SwiftUI

/// The Galleria del Catalogo: every Variante at 64 pt in greys, filtered by Categoria or by blocco of the elenco,
/// and the chosen one large and live.
///
/// It checks each block of Forme: whether the silhouette reads at small size and the halo has no streaks. With a blocco
/// chosen it shows its 24 Varianti in the elenco's order, those still to draw as empty cells (#400).
/// Choosing a Variante asks the large Orb for it, so the change runs through the Regia del Morph.
struct GalleriaView: View {
    let catalogo: Catalogo
    /// The planned Varianti; `nil` when the bundle lacks them, and the Galleria shows the Catalogo alone.
    let elenco: CatalogoElenco?

    /// Where the Snapshotter comes from; it lives as long as the app, like the Catalogo.
    private static let snapshotter = Result { try OrbSnapshotter() }

    @State private var categoria: Categoria?
    @State private var blocco: Int?
    @State private var selection: GalleriaCell.ID?
    /// The large Orb's own controls: the Galleria never changes the Panel's Orb.
    @State private var controls = GalleriaView.makeControls()

    private var shown: [GalleriaCell] {
        GalleriaCell.cells(of: catalogo, elenco: elenco, blocco: blocco, categoria: categoria)
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Spacing.small) {
                filters
                    .padding([.top, .horizontal], Spacing.medium)

                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 64, maximum: 64), spacing: Spacing.small)],
                              spacing: Spacing.small) {
                        ForEach(shown) { cell in
                            Button {
                                selection = cell.id
                                controls.variante = cell.variante
                            } label: {
                                if let variante = cell.variante {
                                    GalleriaThumbnail(variante: variante, snapshotter: try? Self.snapshotter.get())
                                } else if let voce = cell.voce {
                                    GalleriaPlaceholder(voce: voce)
                                }
                            }
                            .buttonStyle(.plain)
                            .overlay {
                                RoundedRectangle(cornerRadius: CornerRadius.small)
                                    .strokeBorder(Palette.lineStrong, lineWidth: 1)
                                    .opacity(selection == cell.id ? 1 : 0)
                            }
                            .accessibilityLabel(label(of: cell))
                            .accessibilityAddTraits(selection == cell.id ? .isSelected : [])
                        }
                    }
                    .padding(Spacing.medium)
                }
            }
            .frame(minWidth: 320)

            VStack(spacing: 0) {
                GalleriaOrbView(controls: controls)
                    .frame(width: 360, height: 360)
                    .accessibilityElement()
                    .accessibilityLabel(Text(controls.variante?.label ?? "Blob"))
                if let cell = shown.first(where: { $0.id == selection }) {
                    GalleriaVoceDetail(cell: cell)
                }
                Spacer(minLength: 0)
            }
            .frame(width: 360)
        }
        .background(Palette.ink)
        .environment(\.colorScheme, .dark) // the halo reads only on the dark of the Notte direction
        .frame(minHeight: 400)
    }

    private var filters: some View {
        HStack(spacing: Spacing.small) {
            Picker("Categoria", selection: $categoria) {
                Text("Tutte").tag(Categoria?.none)
                ForEach(Categoria.allCases, id: \.self) { categoria in
                    Text(verbatim: categoria.rawValue.capitalized).tag(Optional(categoria))
                }
            }
            .fixedSize()
            if let elenco {
                Picker("Blocco", selection: $blocco) {
                    Text("Tutti").tag(Int?.none)
                    ForEach(elenco.blocchi) { blocco in
                        Text(verbatim: blocco.numero.formatted()).tag(Optional(blocco.numero))
                    }
                }
                .fixedSize()
                if let blocco = blocco.flatMap(elenco.blocco(_:)) {
                    Text("\(GalleriaCell.drawnCount(of: blocco, in: catalogo))/\(blocco.varianti.count) disegnate")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(Palette.textSecondary)
                }
            }
        }
    }

    /// What VoiceOver says of a cell: the Variante's name, and for an empty cell that it is still to draw.
    private func label(of cell: GalleriaCell) -> Text {
        if let variante = cell.variante {
            Text(variante.label)
        } else {
            Text("\(cell.nome), da disegnare")
        }
    }

    /// Controls held in Ascolto: in Riposo the Orb would go back to the Blob after 5 s.
    private static func makeControls() -> OrbControls {
        let controls = OrbControls()
        controls.state = .listening
        return controls
    }
}
#endif
