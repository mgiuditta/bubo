import Foundation
import Testing
@testable import Bubo

struct PanelBubbleLayoutTests {
    /// A 900×600 visible frame shifted off the origin, as in `PanelZoneTests`.
    let screen = CGRect(x: 100, y: 50, width: 900, height: 600)
    let bubble = CGSize(width: 360, height: 180)

    private func panelFrame(in zone: PanelZone, size: PanelSize = .normal) -> CGRect {
        PanelSpot(screen: PanelScreen(id: "main", visibleFrame: screen), zone: zone, size: size).panelFrame
    }

    @Test(arguments: [
        (PanelZone.topLeft, PanelBubbleSide.below), (.top, .below), (.topRight, .below),
        (.left, .right), (.center, .above), (.right, .left),
        (.bottomLeft, .above), (.bottom, .above), (.bottomRight, .above),
    ])
    func eachZoneOpensOnItsSide(zone: PanelZone, side: PanelBubbleSide) {
        #expect(zone.bubbleSide == side)
    }

    @Test(arguments: PanelZone.allCases.filter { $0 != .center })
    func theBubbleOpensTowardTheCenter(zone: PanelZone) {
        let panel = panelFrame(in: zone)
        let frame = PanelBubbleLayout.frame(ofSize: bubble, besidePanel: panel, in: zone, visibleFrame: screen)
        switch zone.bubbleSide {
        case .above, .below:
            #expect(abs(frame.midY - screen.midY) < abs(panel.midY - screen.midY))
        case .left, .right:
            #expect(abs(frame.midX - screen.midX) < abs(panel.midX - screen.midX))
        }
    }

    @Test(arguments: PanelZone.allCases)
    func theBubbleStaysInsideTheVisibleFrame(zone: PanelZone) {
        let frame = PanelBubbleLayout.frame(ofSize: bubble, besidePanel: panelFrame(in: zone), in: zone,
                                            visibleFrame: screen)
        #expect(screen.contains(frame))
    }

    @Test(arguments: PanelZone.allCases, PanelSize.allCases)
    func theBubbleNeverCoversTheClickCircle(zone: PanelZone, size: PanelSize) {
        let panel = panelFrame(in: zone, size: size)
        let frame = PanelBubbleLayout.frame(ofSize: bubble, besidePanel: panel, in: zone, visibleFrame: screen)
        let radius = size.clickRadius
        // The point of the bubble nearest to the circle's center stays out of the circle.
        let nearest = CGPoint(x: min(max(panel.midX, frame.minX), frame.maxX),
                              y: min(max(panel.midY, frame.minY), frame.maxY))
        #expect(hypot(nearest.x - panel.midX, nearest.y - panel.midY) > radius)
    }

    @Test(arguments: PanelZone.allCases.filter { $0 != .center }, PanelSize.allCases)
    func theBubbleLeavesTheOrbInSight(zone: PanelZone, size: PanelSize) {
        let panel = panelFrame(in: zone, size: size)
        let frame = PanelBubbleLayout.frame(ofSize: bubble, besidePanel: panel, in: zone, visibleFrame: screen)
        #expect(!frame.intersects(panel))
    }

    @Test func onlyTheReducedBubbleHasAMaxHeight() {
        #expect(PanelBubbleLayout.maxHeight(for: .normal, visibleFrame: screen) == nil)
        #expect(PanelBubbleLayout.maxHeight(for: .reduced, visibleFrame: screen) == 240)
    }

    @Test func onA13InchScreenTheBubbleStopsAt40Percent() throws {
        // A MacBook Air 13" at 1470×956, less the menu bar and a Dock below.
        let air = CGRect(x: 0, y: 70, width: 1470, height: 853)
        let maxHeight = try #require(PanelBubbleLayout.maxHeight(for: .reduced, visibleFrame: air))
        #expect(maxHeight <= air.height * 0.4)
        let tall = CGSize(width: 360, height: maxHeight)
        let panel = PanelSpot(screen: PanelScreen(id: "air", visibleFrame: air), zone: .bottomRight,
                              size: .reduced).panelFrame
        let frame = PanelBubbleLayout.frame(ofSize: tall, besidePanel: panel, in: .bottomRight, visibleFrame: air)
        #expect(air.contains(frame))
    }
}
