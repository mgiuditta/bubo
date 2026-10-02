import AppKit
import Carbon.HIToolbox

/// What else may answer Bubo's shortcut (spec 08): Carbon registers it even when another app has the same combination,
/// and both get the press, so Bubo can only warn.
///
/// Both checks need no permission.
enum ShortcutConflicts {
    /// An app whose default shortcut is ⌥Spazio.
    struct App: Equatable {
        /// The name the warning shows.
        let name: String
        /// Every bundle id the app ships under.
        let bundleIdentifiers: [String]
    }

    /// A system-wide shortcut from Impostazioni di Sistema › Tastiera.
    struct SystemHotKey: Equatable {
        let keyCode: UInt32
        /// Carbon modifiers, possibly with bits beyond ⌘⌥⌃⇧, such as fn.
        let modifiers: UInt32
        let isEnabled: Bool
    }

    /// What else answers Bubo's shortcuts.
    struct Report: Equatable {
        /// The installed apps that take ⌥Spazio too; empty when the shortcut is not ⌥Spazio.
        var apps: [String] = []
        /// Bubo's shortcuts that are also enabled system shortcuts.
        var systemShortcuts: [KeyShortcut] = []

        var isEmpty: Bool { apps.isEmpty && systemShortcuts.isEmpty }
    }

    /// What else answers `shortcuts`, the first being the one that shows and hides the HUD.
    static func report(for shortcuts: [KeyShortcut], installedApps: () -> [String] = { installedApps() },
                       systemHotKeys: () -> [SystemHotKey] = { systemHotKeys() }) -> Report {
        let system = systemHotKeys()
        return Report(apps: shortcuts.first == .showHUD ? installedApps() : [],
                      systemShortcuts: shortcuts.filter { isSystemShortcut($0, among: system) })
    }

    /// The apps that take ⌥Spazio out of the box, by bundle id.
    ///
    /// `com.openai.chat` was read on a Mac with `mdls`; the others come from secondary sources (preflight of #105).
    static let apps: [App] = [
        App(name: "ChatGPT", bundleIdentifiers: ["com.openai.chat"]),
        App(name: "Raycast", bundleIdentifiers: ["com.raycast.macos"]),
        App(name: "Alfred", bundleIdentifiers: ["com.runningwithcrayons.Alfred"]),
        App(name: "Superwhisper", bundleIdentifiers: ["com.superduper.superwhisper"]),
    ]

    /// The names of `apps` installed on this Mac, found through `locate`.
    static func installedApps(locate: (String) -> URL? = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) })
        -> [String] {
        apps.filter { $0.bundleIdentifiers.contains { locate($0) != nil } }.map(\.name)
    }

    /// Whether an enabled system shortcut among `systemHotKeys` is `shortcut`.
    static func isSystemShortcut(_ shortcut: KeyShortcut, among systemHotKeys: [SystemHotKey] = systemHotKeys())
        -> Bool {
        let relevant = UInt32(cmdKey | optionKey | controlKey | shiftKey)
        return systemHotKeys.contains {
            $0.isEnabled && $0.keyCode == shortcut.keyCode && $0.modifiers & relevant == shortcut.carbonModifiers & relevant
        }
    }

    /// The system-wide shortcuts, from `CopySymbolicHotKeys`; empty if the system does not say.
    static func systemHotKeys() -> [SystemHotKey] {
        var array: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&array) == noErr,
              let entries = array?.takeRetainedValue() as? [[String: Any]]
        else { return [] }
        return entries.compactMap { entry in
            guard let code = entry[kHISymbolicHotKeyCode as String] as? NSNumber,
                  let modifiers = entry[kHISymbolicHotKeyModifiers as String] as? NSNumber
            else { return nil }
            return SystemHotKey(keyCode: code.uint32Value, modifiers: modifiers.uint32Value,
                                isEnabled: entry[kHISymbolicHotKeyEnabled as String] as? Bool ?? false)
        }
    }
}
