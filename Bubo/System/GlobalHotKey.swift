import Carbon.HIToolbox

/// One system-wide shortcut registered through Carbon.
///
/// Carbon hot keys need no Accessibility permission, unlike event taps.
// ponytail: one hot key per instance; a table keyed by EventHotKeyID when Bubo needs several.
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

    /// Creates an unregistered hot key that runs `press` on the main thread when pressed, and `release` when let go.
    init(press: @escaping () -> Void, release: @escaping () -> Void = {}) {
        self.press = press
        self.release = release
    }

    /// Registers `shortcut`, replacing any shortcut this instance held before.
    func register(_ shortcut: KeyShortcut) throws(RegistrationError) {
        unregister()
        try installHandlerIfNeeded()
        let id = EventHotKeyID(signature: OSType(0x4255_424F), id: 1) // "BUBO"
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.carbonModifiers, id, GetApplicationEventTarget(), 0, &ref)
        switch status {
        case noErr: hotKey = ref
        case OSStatus(eventHotKeyExistsErr): throw .alreadyInUse
        default: throw .failed(status)
        }
    }

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
            let isPress = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            // Carbon delivers application events on the main thread.
            MainActor.assumeIsolated {
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue()
                isPress ? hotKey.press() : hotKey.release()
            }
            return noErr
        }, specs.count, &specs, context, &handler)
        guard status == noErr else { throw .failed(status) }
    }

    isolated deinit {
        unregister()
        if let handler { RemoveEventHandler(handler) }
    }
}
