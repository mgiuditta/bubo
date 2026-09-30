#if DEBUG
import MetalKit
import SwiftUI

/// The live, monochrome Orb of the Galleria's large view; `controls` drives it as the Panel's drives the Panel.
struct GalleriaOrbView: NSViewRepresentable {
    let controls: OrbControls

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        // The view holds its delegate weakly, so the coordinator keeps the renderer alive.
        context.coordinator.renderer = try? OrbRenderer(view: view, controls: controls, isMonochrome: true)
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Owns the renderer for as long as the view lives.
    final class Coordinator {
        var renderer: OrbRenderer?
    }
}
#endif
