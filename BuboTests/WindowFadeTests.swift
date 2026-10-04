import AppKit
import Testing
@testable import Bubo

@MainActor
struct WindowFadeTests {
    @Test func withRiduciMovimentoWindowsComeAndGoAtOnce() {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 10, height: 10), styleMask: .borderless,
                              backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.orderFrontFading(reducesMotion: true)
        #expect(window.isVisible)
        #expect(window.alphaValue == 1)
        var isDone = false
        window.orderOutFading(reducesMotion: true) { isDone = true }
        #expect(!window.isVisible)
        #expect(window.alphaValue == 1, "Ready for the next opening")
        #expect(isDone)
    }
}
