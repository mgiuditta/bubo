import AppKit
import Carbon.HIToolbox
import Testing
@testable import Bubo

struct KeyShortcutTests {
    @Test func defaultShortcutIsOptionSpace() {
        #expect(KeyShortcut.showHUD.displayName == "⌥Spazio")
    }

    @Test func rawValueRoundTrips() {
        let shortcut = KeyShortcut(keyCode: 11, carbonModifiers: UInt32(cmdKey | shiftKey), keyLabel: "B")
        #expect(KeyShortcut(rawValue: shortcut.rawValue) == shortcut)
    }

    @Test(arguments: ["", "abc", "1:2", "x:2:B"])
    func malformedRawValueIsRejected(rawValue: String) {
        #expect(KeyShortcut(rawValue: rawValue) == nil)
    }

    @Test func shortcutWithoutCommandOptionOrControlIsRejected() {
        #expect(KeyShortcut(keyCode: 11, modifierFlags: [.shift], characters: "b") == nil)
        #expect(KeyShortcut(keyCode: 11, modifierFlags: [], characters: "b") == nil)
    }

    @Test func recordedShortcutShowsModifiersInMacOrder() throws {
        let shortcut = try #require(KeyShortcut(keyCode: 11, modifierFlags: [.command, .shift, .option, .control], characters: "b"))
        #expect(shortcut.displayName == "⌃⌥⇧⌘B")
    }

    @Test func labelWithColonSurvivesRoundTrip() throws {
        let shortcut = KeyShortcut(keyCode: 41, carbonModifiers: UInt32(cmdKey), keyLabel: ":")
        #expect(try #require(KeyShortcut(rawValue: shortcut.rawValue)).keyLabel == ":")
    }
}
