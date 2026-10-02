import AppKit
import SwiftUI
import Testing
@testable import Bubo

@MainActor
struct PanelBubbleTests {
    @Test func theWindowTakesTheKeyboardWithoutActivating() {
        let window = PanelBubbleWindow.make(content: EmptyView())
        #expect(window.styleMask.contains(.nonactivatingPanel))
        #expect(window.canBecomeKey)
        #expect(!window.becomesKeyOnlyIfNeeded)
        #expect(!window.hidesOnDeactivate)
        #expect(window.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(window.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(window.accessibilityLabel() == String(localized: "Domanda nel Panel"))
    }

    @Test func escClosesTheBubble() {
        let bubble = PanelBubble()
        let window = PanelBubbleWindow.make(content: EmptyView())
        window.onCancel = bubble.close
        bubble.open(focus: .prompt)
        window.cancelOperation(nil)
        #expect(!bubble.isOpen)
        #expect(!bubble.takesKeyboard)
    }

    @Test func openingWithoutFocusLeavesTheKeyboardWhereItIs() {
        let bubble = PanelBubble()
        bubble.open(focus: .none)
        #expect(bubble.isOpen)
        #expect(!bubble.takesKeyboard)
        bubble.open(focus: .prompt)
        #expect(bubble.takesKeyboard)
    }

    @Test(arguments: [
        ("", "", false, true),
        ("  ", "", false, true),
        ("ciao", "", false, false),
        ("", "Risposta", false, false),
        ("", "", true, false),
    ])
    func losingTheKeyboardClosesOnlyAnEmptyBubble(prompt: String, answer: String, isAnswering: Bool, closes: Bool) {
        #expect(PanelBubble.closesOnLosingKeyboard(prompt: prompt, answer: answer, isAnswering: isAnswering) == closes)
    }

    @Test func losingTheKeyboardKeepsABubbleWithAllegati() {
        #expect(!PanelBubble.closesOnLosingKeyboard(prompt: "", answer: "", isAnswering: false, hasAttachments: true))
    }

    @Test func losingTheKeyboardKeepsABubbleWithADomanda() {
        let bubble = PanelBubble()
        bubble.open(focus: .prompt)
        bubble.loseKeyboard(closes: false)
        #expect(bubble.isOpen)
        #expect(!bubble.takesKeyboard)
    }

    @Test func anAnswerStartedElsewhereOpensTheBubbleWithoutTakingTheKeyboard() {
        let bubble = PanelBubble()
        bubble.follow(isAnswering: true, isSpeaking: false, panelIsVisible: true)
        #expect(bubble.isOpen)
        #expect(!bubble.takesKeyboard)
    }

    @Test func aSubtitleOpensTheBubbleWithoutTakingTheKeyboard() {
        let bubble = PanelBubble()
        bubble.follow(isAnswering: false, isSpeaking: true, panelIsVisible: true)
        #expect(bubble.isOpen)
        #expect(!bubble.takesKeyboard)
    }

    @Test func aClosedBubbleStaysClosedWhileTheSameAnswerGoesOn() {
        let bubble = PanelBubble()
        bubble.follow(isAnswering: true, isSpeaking: false, panelIsVisible: true)
        bubble.close()
        bubble.follow(isAnswering: true, isSpeaking: true, panelIsVisible: true)
        #expect(!bubble.isOpen)
    }

    @Test func anAnswerWithTheHUDOpenLeavesTheBubbleClosed() {
        let bubble = PanelBubble()
        bubble.follow(isAnswering: true, isSpeaking: false, panelIsVisible: false)
        #expect(!bubble.isOpen)
    }

    @Test(arguments: [true, false])
    func reduceMotionOnlyFades(reducesMotion: Bool) {
        let bubble = PanelBubble()
        bubble.open(focus: .none, reducesMotion: reducesMotion)
        #expect(bubble.appearance == (reducesMotion ? .fade : .grow))
    }

    @Test func theEndOfAnAnswerIsAnnouncedOnce() {
        #expect(PanelBubble.announcement(wasAnswering: true, isAnswering: false, answer: "Fatto")
                == String(localized: "Risposta pronta"))
        #expect(PanelBubble.announcement(wasAnswering: true, isAnswering: true, answer: "Fat") == nil)
        #expect(PanelBubble.announcement(wasAnswering: false, isAnswering: false, answer: "Fatto") == nil)
        #expect(PanelBubble.announcement(wasAnswering: true, isAnswering: false, answer: "") == nil)
    }
}
