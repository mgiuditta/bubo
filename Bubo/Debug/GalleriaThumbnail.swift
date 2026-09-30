#if DEBUG
import SwiftUI

/// One cell of the Galleria: a still of the Variante at 64 pt, without text.
struct GalleriaThumbnail: View {
    let variante: Variante
    /// Draws the still; `nil` without Metal, which leaves the cell on its spinner.
    let snapshotter: OrbSnapshotter?

    @Environment(\.displayScale) private var displayScale
    @State private var image: CGImage?

    var body: some View {
        ZStack {
            if let image {
                Image(decorative: image, scale: displayScale)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .frame(width: 64, height: 64)
        .contentShape(.rect)
        .task(id: displayScale) {
            image = await snapshotter?.snapshot(of: variante, pixelSize: Int(64 * displayScale))
        }
    }
}
#endif
