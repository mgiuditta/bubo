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

    private let action: () -> Void
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    /// Creates an unregistered hot key that runs `action` on the main thread when pressed.
    init(action: @escaping () -> Void) {
        self.action = action
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
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            // Carbon delivers application events on the main thread.
            MainActor.assumeIsolated {
                Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue().action()
            }
            return noErr
        }, 1, &spec, context, &handler)
        guard status == noErr else { throw .failed(status) }
    }

    isolated deinit {
        unregister()
        if let handler { RemoveEventHandler(handler) }
    }
}
