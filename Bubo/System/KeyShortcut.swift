import AppKit
import Carbon.HIToolbox

/// A global keyboard shortcut: a key plus at least one of ⌘, ⌥, ⌃.
///
/// Stored in `UserDefaults` through `rawValue`, and registered with Carbon.
nonisolated struct KeyShortcut: Hashable, Sendable {
    /// The virtual key code, as in `kVK_Space`.
    let keyCode: UInt32
    /// The Carbon modifier mask (`cmdKey`, `optionKey`, `controlKey`, `shiftKey`).
    let carbonModifiers: UInt32
    /// The key as the user saw it when recording, such as `Spazio` or `B`.
    let keyLabel: String

    /// ⌥Spazio, the default shortcut that shows and hides the HUD.
    static let showHUD = KeyShortcut(keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(optionKey), keyLabel: "Spazio")

    /// Esc alone, which stops Bubo's voice while it speaks (spec 08); never a shortcut the user records.
    static let escape = KeyShortcut(keyCode: UInt32(kVK_Escape), carbonModifiers: 0, keyLabel: "⎋")

    /// The same combination plus ⇧, which held only dictates into the prompt (spec 08); `nil` when it has ⇧ already.
    var dictationVariant: KeyShortcut? {
        guard carbonModifiers & UInt32(shiftKey) == 0 else { return nil }
        return KeyShortcut(keyCode: keyCode, carbonModifiers: carbonModifiers | UInt32(shiftKey), keyLabel: keyLabel)
    }

    /// The shortcut as shown in menus and settings, such as `⌥Spazio`.
    var displayName: String {
        var symbols = ""
        if carbonModifiers & UInt32(controlKey) != 0 { symbols += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { symbols += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { symbols += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { symbols += "⌘" }
        return symbols + keyLabel
    }

    /// Creates a shortcut from a key press, or `nil` when it has no ⌘, ⌥ or ⌃,
    /// because a global shortcut without them would swallow normal typing.
    init?(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags, characters: String?) {
        let modifiers = Self.carbonModifiers(from: modifierFlags)
        guard modifiers & UInt32(cmdKey | optionKey | controlKey) != 0 else { return nil }
        self.init(
            keyCode: UInt32(keyCode),
            carbonModifiers: modifiers,
            keyLabel: Self.label(forKeyCode: keyCode, characters: characters)
        )
    }

    init(keyCode: UInt32, carbonModifiers: UInt32, keyLabel: String) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.keyLabel = keyLabel
    }

    /// Converts AppKit modifier flags to the Carbon mask used for registration.
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mask: UInt32 = 0
        if flags.contains(.command) { mask |= UInt32(cmdKey) }
        if flags.contains(.option) { mask |= UInt32(optionKey) }
        if flags.contains(.control) { mask |= UInt32(controlKey) }
        if flags.contains(.shift) { mask |= UInt32(shiftKey) }
        return mask
    }

    private static func label(forKeyCode keyCode: UInt16, characters: String?) -> String {
        switch Int(keyCode) {
        case kVK_Space: "Spazio"
        case kVK_Return: "↩"
        case kVK_Tab: "⇥"
        case kVK_Escape: "⎋"
        case kVK_LeftArrow: "←"
        case kVK_RightArrow: "→"
        case kVK_UpArrow: "↑"
        case kVK_DownArrow: "↓"
        default: characters?.uppercased() ?? "?"
        }
    }
}

extension KeyShortcut: RawRepresentable {
    /// Decodes `keyCode:modifiers:label`.
    init?(rawValue: String) {
        let parts = rawValue.split(separator: ":", maxSplits: 2).map(String.init)
        guard parts.count == 3, let keyCode = UInt32(parts[0]), let modifiers = UInt32(parts[1]) else { return nil }
        self.init(keyCode: keyCode, carbonModifiers: modifiers, keyLabel: parts[2])
    }

    /// Encodes the shortcut as `keyCode:modifiers:label`.
    var rawValue: String { "\(keyCode):\(carbonModifiers):\(keyLabel)" }
}
