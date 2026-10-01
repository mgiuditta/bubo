import SwiftUI

/// The map in SwiftUI.
struct GalaxyMap: NSViewRepresentable {
    let model: GalaxyModel

    func makeNSView(context: Context) -> GalaxyMapNSView {
        GalaxyMapNSView(model: model)
    }

    func updateNSView(_ view: GalaxyMapNSView, context: Context) {}
}
