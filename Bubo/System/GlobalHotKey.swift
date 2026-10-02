import Carbon.HIToolbox

/// One system-wide shortcut registered through Carbon.
///
/// Carbon hot keys need no Accessibility permission, unlike event taps.
/// Each instance holds one shortcut, under its own `EventHotKeyID`, and runs only for that one.
final class GlobalHotKey {
    /// Why a shortcut could not be registered.
    enum RegistrationError: Error {
        /// Another app already owns this shortcut.
        case alreadyInUse
        /// Carbon refused for another reason.
        case failed(OSStatus)
    }

    private let press: () -> Void
    private let release: () -> Void
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    /// The id Carbon reports with this instance's presses; the other instances' presses pass on.
    private let id = GlobalHotKey.nextID()
    /// The last id given to an instance.
    private static var lastID: UInt32 = 0

    private static func nextID() -> UInt32 {
        lastID += 1
        return lastID
    }

    /// Creates an unregistered hot key that runs `press` on the main thread when pressed, and `release` when let go.
    init(press: @escaping () -> Void, release: @escaping () -> Void = {}) {
        self.press = press
        self.release = release
    }

    /// Registers `shortcut`, replacing any shortcut this instance held before.
    func register(_ shortcut: KeyShortcut) throws(RegistrationError) {
        unregister()
        try installHandlerIfNeeded()
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.carbonModifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        switch status {
        case noErr: hotKey = ref
        case OSStatus(eventHotKeyExistsErr): throw .alreadyInUse
        default: throw .failed(status)
        }
    }

    /// "BUBO", the signature of Bubo's shortcuts.
    private static let signature = OSType(0x4255_424F)

    /// Removes the shortcut, if any.
    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
    }

    private func installHandlerIfNeeded() throws(RegistrationError) {
        guard handler == nil else { return }
        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let context = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let context, let event else { return OSStatus(eventNotHandledErr) }
            var pressed = EventHotKeyID()
            let read = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                         nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed)
            let isPress = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            // Carbon delivers application events on the main thread.
            return MainActor.assumeIsolated {
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue()
                // Every instance's handler sees every press: the others' go on down the chain.
                guard read == noErr, pressed.signature == GlobalHotKey.signature, pressed.id == hotKey.id else {
                    return OSStatus(eventNotHandledErr)
                }
                isPress ? hotKey.press() : hotKey.release()
                return noErr
            }
        }, specs.count, &specs, context, &handler)
        guard status == noErr else { throw .failed(status) }
    }

    isolated deinit {
        unregister()
        if let handler { RemoveEventHandler(handler) }
    }
}
