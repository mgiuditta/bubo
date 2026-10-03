import Carbon.HIToolbox
import Foundation
import Testing
@testable import Bubo

/// The sola dettatura and what else answers Bubo's shortcut (#105), with no real app or system setting read.
struct ShortcutConflictsTests {
    private let optionShiftSpace = KeyShortcut(keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(optionKey | shiftKey),
                                               keyLabel: "Spazio")

    /// A «Chiedi nel Panel» nobody uses on `keyCode`, so the center does not take the real ⌥⇧Spazio.
    private static func unusedAsk(_ keyCode: Int) -> KeyShortcut {
        KeyShortcut(keyCode: UInt32(keyCode), carbonModifiers: UInt32(controlKey | optionKey), keyLabel: "F")
    }

    @Test func theDictationVariantAddsShift() {
        #expect(KeyShortcut.showHUD.dictationVariant == optionShiftSpace)
        #expect(KeyShortcut.showHUD.dictationVariant?.displayName == "⌥⇧Spazio")
    }

    @Test func aShortcutWithShiftHasNoDictation() {
        #expect(optionShiftSpace.dictationVariant == nil)
    }

    @Test func installedAppsAreFoundByBundleID() {
        let installed: Set = ["com.openai.chat", "com.superduper.superwhisper"]
        let apps = ShortcutConflicts.installedApps { installed.contains($0) ? URL(filePath: "/Applications/\($0).app") : nil }
        #expect(apps == ["ChatGPT", "Superwhisper"])
    }

    @Test func onlyEnabledSystemShortcutsCountIgnoringFn() {
        let fn = UInt32(kEventKeyModifierFnMask)
        let space = UInt32(kVK_Space)
        let enabled = ShortcutConflicts.SystemHotKey(keyCode: space, modifiers: UInt32(optionKey) | fn, isEnabled: true)
        let disabled = ShortcutConflicts.SystemHotKey(keyCode: space, modifiers: UInt32(optionKey), isEnabled: false)

        #expect(ShortcutConflicts.isSystemShortcut(.showHUD, among: [enabled]))
        #expect(!ShortcutConflicts.isSystemShortcut(.showHUD, among: [disabled]))
        #expect(!ShortcutConflicts.isSystemShortcut(optionShiftSpace, among: [enabled]))
    }

    @Test func appsMatterOnlyForOptionSpace() {
        let other = KeyShortcut(keyCode: UInt32(kVK_ANSI_B), carbonModifiers: UInt32(controlKey | optionKey), keyLabel: "B")
        let system = [ShortcutConflicts.SystemHotKey(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey | shiftKey),
                                                     isEnabled: true)]

        let onDefault = ShortcutConflicts.report(for: [.showHUD, optionShiftSpace], installedApps: { ["Raycast"] },
                                                 systemHotKeys: { system })
        let onOther = ShortcutConflicts.report(for: [other], installedApps: { ["Raycast"] }, systemHotKeys: { [] })

        #expect(onDefault == ShortcutConflicts.Report(apps: ["Raycast"], systemShortcuts: [optionShiftSpace]))
        #expect(onOther.isEmpty)
    }

    @MainActor @Test func theCenterRegistersTheDictationUnlessTheShortcutHasShift() throws {
        let defaults = try #require(UserDefaults(suiteName: "ShortcutConflictsTests-\(UUID())"))
        // A combination nobody uses, so the test does not take a real one.
        let shortcut = KeyShortcut(keyCode: UInt32(kVK_F19), carbonModifiers: UInt32(controlKey | optionKey), keyLabel: "F19")
        defaults.set(shortcut.rawValue, forKey: HotKeyCenter.defaultsKey)
        defaults.set(Self.unusedAsk(kVK_F12).rawValue, forKey: HotKeyCenter.askDefaultsKey)
        let center = HotKeyCenter(defaults: defaults) { _ in }

        #expect(center.dictationShortcut == shortcut.dictationVariant)

        let withShift = try #require(shortcut.dictationVariant)
        center.change(to: withShift)
        #expect(center.shortcut == withShift)
        #expect(center.dictationShortcut == nil)
    }

    @MainActor @Test func aRefusedChangeKeepsTheOldShortcutAndSaysWhy() throws {
        let defaults = try #require(UserDefaults(suiteName: "ShortcutConflictsTests-\(UUID())"))
        let shortcut = KeyShortcut(keyCode: UInt32(kVK_F18), carbonModifiers: UInt32(controlKey | optionKey), keyLabel: "F18")
        let taken = KeyShortcut(keyCode: UInt32(kVK_F17), carbonModifiers: UInt32(controlKey | optionKey), keyLabel: "F17")
        defaults.set(shortcut.rawValue, forKey: HotKeyCenter.defaultsKey)
        defaults.set(Self.unusedAsk(kVK_F11).rawValue, forKey: HotKeyCenter.askDefaultsKey)
        let other = GlobalHotKey { }
        try other.register(taken)
        let center = HotKeyCenter(defaults: defaults) { _ in }

        center.change(to: taken)

        #expect(center.shortcut == shortcut)
        #expect(center.dictationShortcut == shortcut.dictationVariant)
        #expect(center.problem != nil)
        other.unregister()
    }

    @Test func askInPanelDefaultsToTheDictationVariantOfTheHUD() {
        #expect(KeyShortcut.askInPanel == KeyShortcut.showHUD.dictationVariant)
        #expect(KeyShortcut.askInPanel.displayName == "⌥⇧Spazio")
    }

    @MainActor @Test func theBollaTakesTheSolaDettaturaAndGivesItBack() throws {
        let defaults = try #require(UserDefaults(suiteName: "ShortcutConflictsTests-\(UUID())"))
        let shortcut = KeyShortcut(keyCode: UInt32(kVK_F16), carbonModifiers: UInt32(controlKey | optionKey), keyLabel: "F16")
        let variant = try #require(shortcut.dictationVariant)
        let other = KeyShortcut(keyCode: UInt32(kVK_F15), carbonModifiers: UInt32(controlKey | optionKey), keyLabel: "F15")
        defaults.set(shortcut.rawValue, forKey: HotKeyCenter.defaultsKey)
        defaults.set(variant.rawValue, forKey: HotKeyCenter.askDefaultsKey)
        let center = HotKeyCenter(defaults: defaults) { _ in }

        #expect(center.askShortcut == variant)
        #expect(center.dictationShortcut == nil)

        center.changeAsk(to: other)
        #expect(center.askShortcut == other)
        #expect(center.dictationShortcut == variant)
        #expect(defaults.string(forKey: HotKeyCenter.askDefaultsKey) == other.rawValue)

        center.changeAsk(to: variant)
        #expect(center.dictationShortcut == nil)
        #expect(center.problem == nil)
    }

    @MainActor @Test func theHUDAndTheBollaNeverShareAShortcut() throws {
        let defaults = try #require(UserDefaults(suiteName: "ShortcutConflictsTests-\(UUID())"))
        let shortcut = KeyShortcut(keyCode: UInt32(kVK_F14), carbonModifiers: UInt32(controlKey | optionKey), keyLabel: "F14")
        let ask = KeyShortcut(keyCode: UInt32(kVK_F13), carbonModifiers: UInt32(controlKey | optionKey), keyLabel: "F13")
        defaults.set(shortcut.rawValue, forKey: HotKeyCenter.defaultsKey)
        defaults.set(ask.rawValue, forKey: HotKeyCenter.askDefaultsKey)
        let center = HotKeyCenter(defaults: defaults) { _ in }

        center.changeAsk(to: shortcut)
        #expect(center.askShortcut == ask)
        #expect(center.problem != nil)

        center.change(to: ask)
        #expect(center.shortcut == shortcut)
        #expect(center.problem != nil)
    }
}
