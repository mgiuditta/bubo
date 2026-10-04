import AppKit
import Testing
@testable import Bubo

/// The VoiceOver actions of the Orb in the Panel (#639).
@MainActor
struct OrbPanelViewAccessibilityTests {
    /// Which of the view's closures ran.
    final class Calls {
        var names: [String] = []
    }

    func makeView(recording calls: Calls) -> OrbPanelView {
        let view = OrbPanelView(frame: CGRect(x: 0, y: 0, width: 120, height: 120), device: nil)
        view.onPress = { calls.names.append("press") }
        view.onOpenHUD = { calls.names.append("openHUD") }
        view.onAsk = { calls.names.append("ask") }
        return view
    }

    func perform(_ name: String, on view: OrbPanelView) throws {
        let action = try #require(view.accessibilityCustomActions()?.first { $0.name == name })
        let handler = try #require(action.handler)
        #expect(handler())
    }

    @Test func openHUDOpensTheHUDNotTheBubble() throws {
        let calls = Calls()
        try perform(String(localized: "Apri HUD"), on: makeView(recording: calls))
        #expect(calls.names == ["openHUD"])
    }

    @Test func askInPanelOpensTheBubble() throws {
        let calls = Calls()
        try perform(String(localized: "Chiedi nel Panel"), on: makeView(recording: calls))
        #expect(calls.names == ["ask"])
    }
}
