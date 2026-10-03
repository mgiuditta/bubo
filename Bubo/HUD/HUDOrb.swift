import MetalKit
import SwiftUI

/// The live Orb at the centre of the HUD rings: the same Stato, Tinta and Variante as the Panel's.
struct HUDOrb: View {
    var controls: OrbControls = .shared
    @Environment(\.accessibilityReduceMotion) private var systemReducesMotion
    @AppStorage(Motion.reducesMotionKey) private var reducesMotion = false

    var body: some View {
        ZStack {
            HUDRings(isAnimated: !(systemReducesMotion || reducesMotion))
            OrbMetalView(controls: controls)
                .padding(60)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(Text("Orb di Bubo", comment: "VoiceOver label of the Orb in the HUD; its value is the Stato."))
        .accessibilityValue(Text(controls.displayedState.title))
        .accessibilityAddTraits(.isImage)
    }
}

/// The Metal view of the HUD's Orb, drawn by its own `OrbRenderer` from the shared controls.
private struct OrbMetalView: NSViewRepresentable {
    let controls: OrbControls

    func makeNSView(context: Context) -> HUDOrbView {
        let view = HUDOrbView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        // The view holds its delegate weakly, so the coordinator keeps the renderer alive.
        let renderer = try? OrbRenderer(view: view, controls: controls)
        context.coordinator.renderer = renderer
        view.renderer = renderer
        return view
    }

    func updateNSView(_ view: HUDOrbView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Owns the renderer for as long as the view lives.
    final class Coordinator {
        var renderer: OrbRenderer?
    }
}

/// An `MTKView` drawn below Retina, as the Panel is, and paused while its window is hidden or covered; the Orb leans
/// a little toward the pointer passing over it.
final class HUDOrbView: MTKView {
    /// The renderer told when the window is hidden or covered; the coordinator owns it.
    weak var renderer: OrbRenderer?

    override func setFrameSize(_ size: NSSize) {
        super.setFrameSize(size)
        autoResizeDrawable = false
        drawableSize = CGSize(width: size.width * OrbPanelController.renderScale,
                              height: size.height * OrbPanelController.renderScale)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: nil)
        guard let window else { return }
        NotificationCenter.default.addObserver(self, selector: #selector(occlusionDidChange),
                                               name: NSWindow.didChangeOcclusionStateNotification, object: window)
        occlusionDidChange()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { follow(event) }
    override func mouseMoved(with event: NSEvent) { follow(event) }
    override func mouseExited(with event: NSEvent) { renderer?.pointer = nil }

    /// Tells the renderer where the pointer is, from the view's centre: -1…1 on each axis, y up.
    private func follow(_ event: NSEvent) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let location = convert(event.locationInWindow, from: nil)
        let x = (location.x - bounds.midX) / (bounds.width / 2)
        var y = (location.y - bounds.midY) / (bounds.height / 2)
        if isFlipped { y = -y }
        renderer?.pointer = SIMD2(Float(min(max(x, -1), 1)), Float(min(max(y, -1), 1)))
    }

    @objc private func occlusionDidChange() {
        renderer?.isVisible = window?.occlusionState.contains(.visible) == true
    }
}
