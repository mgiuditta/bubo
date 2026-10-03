import MetalKit

/// The Metal view inside the Panel: a click opens the HUD, a drag moves the Panel, a right click opens the menu, and
/// what is dropped on it becomes an Allegato.
///
/// Reads as a button to VoiceOver, with the same menu as its secondary action and "Apri HUD", "Chiedi nel Panel" and the
/// switch to the other size among its actions.
final class OrbPanelView: MTKView {
    /// Called when the Orb is clicked or pressed by VoiceOver.
    var onPress: () -> Void = {}
    /// Called by the VoiceOver action "Chiedi nel Panel", to open the bubble.
    var onAsk: () -> Void = {}
    /// Called by the VoiceOver action that switches the Panel to the other size.
    var onToggleSize: () -> Void = {}
    /// What VoiceOver hears about the Sessioni after the Orb's Stato, such as "2 Sessioni ti attendono"; `nil` when
    /// none waits or fails.
    var sessionsDescription: String?
    /// The Panel's size, which names the action that switches it.
    var size = PanelPlacement.defaultSize {
        didSet { placeRecordingDot() }
    }
    /// Whether a Riunione is being recorded: a red dot on the Orb, and VoiceOver hears it after the Orb's Stato.
    var isRecordingMeeting = false {
        didSet {
            guard isRecordingMeeting != oldValue else { return }
            recordingDot.isHidden = !isRecordingMeeting
            placeRecordingDot()
        }
    }
    /// Called when a drag of the Panel ends, to snap it to the grid.
    var onDragEnd: () -> Void = {}
    /// Called when the pointer moves over the Panel or leaves it, to update the click circle.
    var onPointerMove: () -> Void = {}
    /// Called when a drag enters the Orb, before anything is dropped.
    var onDropEnter: () -> Void = {}
    /// Called when a drag leaves the Orb without dropping.
    var onDropExit: () -> Void = {}
    /// Called with what is dropped on the Orb; returns whether it became Allegati.
    var onDrop: (NSPasteboard) -> Bool = { _ in false }

    /// The press under way, in screen coordinates; `nil` when the button is up.
    private var press: PanelPress?
    /// Where the pointer grabbed the Panel, from the window's origin.
    private var grabOffset = CGPoint.zero
    /// The red dot of a Riunione being recorded, as in the menu bar; hidden otherwise.
    private lazy var recordingDot: NSView = {
        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor(Palette.danger).cgColor
        // A dark ring keeps the dot apart from a light Orb.
        dot.layer?.borderColor = NSColor(Palette.ink).cgColor
        dot.isHidden = true
        addSubview(dot)
        return dot
    }()

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        placeRecordingDot()
    }

    /// Puts the dot at the top right of the Orb, sized for the Panel.
    private func placeRecordingDot() {
        guard isRecordingMeeting else { return }
        let diameter: CGFloat = size == .reduced ? 9 : 14
        // On the Orb's edge, at 45 degrees: the Orb fills about the click circle.
        let offset = size.clickRadius * 0.62
        recordingDot.frame = CGRect(x: bounds.midX + offset - diameter / 2, y: bounds.midY + offset - diameter / 2,
                                    width: diameter, height: diameter)
        recordingDot.layer?.cornerRadius = diameter / 2
        recordingDot.layer?.borderWidth = size == .reduced ? 1.5 : 2
    }

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

    // A drop never activates Bubo: the Panel is non-activating, and the app the drag comes from stays in front.
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        onDropEnter()
        return .copy
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        onDropExit()
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        onDrop(sender.draggingPasteboard)
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { String(localized: "Bubo") }
    override func accessibilityHelp() -> String? { String(localized: "Apre l'HUD") }
    override func accessibilityValue() -> Any? {
        let state = String(localized: OrbControls.shared.displayedState.title)
        let meeting = isRecordingMeeting ? String(localized: "Registrazione della Riunione in corso") : nil
        return [state, meeting, sessionsDescription].compactMap(\.self).joined(separator: ", ")
    }

    override func accessibilityPerformPress() -> Bool {
        onPress()
        return true
    }

    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        // A verb, as the other actions: a name like "Panel ridotto" would read as the state the Panel is already in.
        let sizeAction = size == .reduced ? String(localized: "Ingrandisci il Panel")
            : String(localized: "Riduci il Panel")
        return [
            NSAccessibilityCustomAction(name: String(localized: "Apri HUD")) { [weak self] in
                self?.onPress()
                return true
            },
            NSAccessibilityCustomAction(name: String(localized: "Chiedi nel Panel")) { [weak self] in
                self?.onAsk()
                return true
            },
            NSAccessibilityCustomAction(name: sizeAction) { [weak self] in
                self?.onToggleSize()
                return true
            },
        ]
    }

    override func accessibilityPerformShowMenu() -> Bool {
        guard let menu else { return false }
        return menu.popUp(positioning: nil, at: CGPoint(x: bounds.midX, y: bounds.midY), in: self)
    }
}
