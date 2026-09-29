import MetalKit

/// The Metal view inside the Panel: drags the Panel and reads as a button to VoiceOver.
final class OrbPanelView: MTKView {
    /// Called when VoiceOver presses the Orb.
    var onPress: () -> Void = {}

    override var mouseDownCanMoveWindow: Bool { true }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { String(localized: "Bubo") }
    override func accessibilityHelp() -> String? { String(localized: "Apre l'HUD") }

    override func accessibilityPerformPress() -> Bool {
        onPress()
        return true
    }
}
