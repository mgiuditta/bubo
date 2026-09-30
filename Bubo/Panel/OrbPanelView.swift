import MetalKit

/// The Metal view inside the Panel: a click opens the HUD, a drag moves the Panel, a right click opens the menu.
///
/// Reads as a button to VoiceOver, with the same menu as its secondary action.
final class OrbPanelView: MTKView {
    /// Called when the Orb is clicked or pressed by VoiceOver.
    var onPress: () -> Void = {}
    /// Called when a drag of the Panel ends, to snap it to the grid.
    var onDragEnd: () -> Void = {}
    /// Called when the pointer moves over the Panel or leaves it, to update the click circle.
    var onPointerMove: () -> Void = {}

    /// The press under way, in screen coordinates; `nil` when the button is up.
    private var press: PanelPress?
    /// Where the pointer grabbed the Panel, from the window's origin.
    private var grabOffset = CGPoint.zero

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseMoved(with event: NSEvent) { onPointerMove() }
    override func mouseExited(with event: NSEvent) { onPointerMove() }

    // The drag is done by hand, not by the window server, so the view tells a click from a drag and hears the release.
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control), let menu {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
            return
        }
        grabOffset = event.locationInWindow
        press = PanelPress(at: NSEvent.mouseLocation)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, var press else { return }
        let pointer = NSEvent.mouseLocation
        press.move(to: pointer)
        self.press = press
        guard press.isDrag else { return }
        window.setFrameOrigin(CGPoint(x: pointer.x - grabOffset.x, y: pointer.y - grabOffset.y))
    }

    override func mouseUp(with event: NSEvent) {
        guard let press else { return }
        self.press = nil
        if press.isDrag { onDragEnd() } else { onPress() }
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { String(localized: "Bubo") }
    override func accessibilityHelp() -> String? { String(localized: "Apre l'HUD") }

    override func accessibilityPerformPress() -> Bool {
        onPress()
        return true
    }

    override func accessibilityPerformShowMenu() -> Bool {
        guard let menu else { return false }
        return menu.popUp(positioning: nil, at: CGPoint(x: bounds.midX, y: bounds.midY), in: self)
    }
}
