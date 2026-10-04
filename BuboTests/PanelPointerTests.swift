import Foundation
import Testing
@testable import Bubo

struct PanelClickCircleTests {
    /// A 240 pt Panel off the origin, centered on (220, 180).
    let panel = CGRect(x: 100, y: 60, width: 240, height: 240)
    let radius = PanelSize.normal.clickRadius

    @Test func centerIsInside() {
        #expect(PanelClickCircle.contains(CGPoint(x: 220, y: 180), inPanel: panel, of: .normal))
    }

    @Test(arguments: [
        CGPoint(x: 100, y: 60),   // the Panel's corner, where the halo fades
        CGPoint(x: 340, y: 300),
        CGPoint(x: 220, y: 60),   // the middle of an edge, beyond the circle
        CGPoint(x: 500, y: 500),  // far off the Panel
    ])
    func pointOutsideCircleIsNotInside(point: CGPoint) {
        #expect(!PanelClickCircle.contains(point, inPanel: panel, of: .normal))
    }

    @Test func pointOnBorderIsInside() {
        #expect(PanelClickCircle.contains(CGPoint(x: 220 + radius, y: 180), inPanel: panel, of: .normal))
        #expect(PanelClickCircle.contains(CGPoint(x: 220, y: 180 - radius), inPanel: panel, of: .normal))
    }

    @Test func pointJustPastBorderIsOutside() {
        #expect(!PanelClickCircle.contains(CGPoint(x: 220 + radius + 0.5, y: 180), inPanel: panel, of: .normal))
    }

    @Test(arguments: PanelSize.allCases)
    func circleFitsInsidePanel(size: PanelSize) {
        #expect(size.clickRadius * 2 <= size.side)
    }

    @Test func reducedCircleKeepsTheNormalShare() {
        let normal = PanelSize.normal.clickRadius / PanelSize.normal.side
        let reduced = PanelSize.reduced.clickRadius / PanelSize.reduced.side
        #expect(abs(normal - reduced) < 0.01)
    }

    @Test func reducedPanelTakesClicksOnlyInItsSmallerCircle() {
        let small = CGRect(x: 100, y: 60, width: 112, height: 112)
        #expect(PanelClickCircle.contains(CGPoint(x: 156 + 37, y: 116), inPanel: small, of: .reduced))
        #expect(!PanelClickCircle.contains(CGPoint(x: 156 + 38, y: 116), inPanel: small, of: .reduced))
    }
}

struct PanelPressTests {
    let start = CGPoint(x: 50, y: 50)

    @Test func pressWithoutMovingIsClick() {
        let press = PanelPress(at: start)
        #expect(!press.isDrag)
    }

    @Test func smallJitterStaysClick() {
        var press = PanelPress(at: start)
        press.move(to: CGPoint(x: 52, y: 51))
        #expect(!press.isDrag)
    }

    @Test func movingPastThresholdIsDrag() {
        var press = PanelPress(at: start)
        press.move(to: CGPoint(x: start.x + PanelPress.dragThreshold, y: start.y))
        #expect(press.isDrag)
    }

    @Test func dragStaysDragWhenPointerComesBack() {
        var press = PanelPress(at: start)
        press.move(to: CGPoint(x: 80, y: 50))
        press.move(to: start)
        #expect(press.isDrag)
    }
}
