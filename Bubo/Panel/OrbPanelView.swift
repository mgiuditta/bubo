import MetalKit

/// The Metal view inside the Panel: drags the Panel and reads as a button to VoiceOver.
final class OrbPanelView: MTKView {
    /// Called when VoiceOver presses the Orb.
    var onPress: () -> Void = {}
    /// Called when a drag of the Panel ends, to snap it to the grid.
    var onDragEnd: () -> Void = {}

    /// Where the pointer grabbed the Panel, from the window's origin; `nil` when no drag is under way.
    private var grabOffset: CGPoint?
    private var isDragging = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // The drag is done by hand, not by the window server, so the view hears the release.
    override func mouseDown(with event: NSEvent) {
        grabOffset = event.locationInWindow
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let grabOffset else { return }
        let pointer = NSEvent.mouseLocation
        window.setFrameOrigin(CGPoint(x: pointer.x - grabOffset.x, y: pointer.y - grabOffset.y))
        isDragging = true
    }

    override func mouseUp(with event: NSEvent) {
        if isDragging { onDragEnd() }
        grabOffset = nil
        isDragging = false
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { String(localized: "Bubo") }
    override func accessibilityHelp() -> String? { String(localized: "Apre l'HUD") }

    override func accessibilityPerformPress() -> Bool {
        onPress()
        return true
    }
}
