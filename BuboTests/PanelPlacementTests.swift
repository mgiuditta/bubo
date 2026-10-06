import Foundation
import Testing
@testable import Bubo

struct PanelZoneTests {
    /// A 900×600 visible frame shifted off the origin, as on a screen below the Dock or menu bar.
    let frame = CGRect(x: 100, y: 50, width: 900, height: 600)

    @Test(arguments: [
        (CGPoint(x: 250, y: 550), PanelZone.topLeft),
        (CGPoint(x: 550, y: 550), .top),
        (CGPoint(x: 850, y: 550), .topRight),
        (CGPoint(x: 250, y: 350), .left),
        (CGPoint(x: 550, y: 350), .center),
        (CGPoint(x: 850, y: 350), .right),
        (CGPoint(x: 250, y: 150), .bottomLeft),
        (CGPoint(x: 550, y: 150), .bottom),
        (CGPoint(x: 850, y: 150), .bottomRight),
    ])
    func pointFallsInItsZone(point: CGPoint, zone: PanelZone) {
        #expect(PanelZone(containing: point, in: frame) == zone)
    }

    @Test(arguments: [
        // Inner lines belong to the zone after them: right of a column line, above a row line.
        (CGPoint(x: 400, y: 350), PanelZone.center),
        (CGPoint(x: 700, y: 350), .right),
        (CGPoint(x: 550, y: 250), .center),
        (CGPoint(x: 550, y: 450), .top),
        // The frame's own edges and corners stay in the outer zones.
        (CGPoint(x: 100, y: 50), .bottomLeft),
        (CGPoint(x: 1000, y: 650), .topRight),
        (CGPoint(x: 1000, y: 50), .bottomRight),
        // Points outside the frame clamp to the nearest zone.
        (CGPoint(x: -500, y: 350), .left),
        (CGPoint(x: 5000, y: -5000), .bottomRight),
    ])
    func pointOnBorderFallsInPredictableZone(point: CGPoint, zone: PanelZone) {
        #expect(PanelZone(containing: point, in: frame) == zone)
    }

    @Test(arguments: PanelZone.allCases)
    func originKeepsPanelInsideVisibleFrame(zone: PanelZone) {
        let origin = zone.panelOrigin(side: 240, in: frame)
        let panel = CGRect(origin: origin, size: CGSize(width: 240, height: 240))
        #expect(frame.contains(panel))
    }

    @Test(arguments: PanelZone.allCases)
    func panelCenterFallsBackInItsZone(zone: PanelZone) {
        let origin = zone.panelOrigin(side: 240, in: frame)
        let center = CGPoint(x: origin.x + 120, y: origin.y + 120)
        #expect(PanelZone(containing: center, in: frame) == zone)
    }

    @Test func cornersAndCenterSitWhereExpected() {
        #expect(PanelZone.bottomRight.panelOrigin(side: 240, in: frame) == CGPoint(x: 760, y: 50))
        #expect(PanelZone.topLeft.panelOrigin(side: 240, in: frame) == CGPoint(x: 100, y: 410))
        #expect(PanelZone.center.panelOrigin(side: 240, in: frame) == CGPoint(x: 430, y: 230))
    }
}

struct PanelPlacementTests {
    let main = PanelScreen(id: "main", visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875))
    let external = PanelScreen(id: "external", visibleFrame: CGRect(x: 1440, y: 0, width: 2560, height: 1415))

    @Test func firstLaunchIsBottomRightOnMainScreen() {
        let spot = PanelPlacement().spot(among: [main, external])
        #expect(spot == PanelSpot(screen: main, zone: .bottomRight))
    }

    @Test func dropSnapsToZoneOfScreenUnderCenter() {
        var placement = PanelPlacement()
        let spot = placement.drop(center: CGPoint(x: 1500, y: 1300), among: [main, external])
        #expect(spot == PanelSpot(screen: external, zone: .topLeft))
        #expect(placement.spot(among: [main, external]) == spot)
    }

    @Test func eachScreenRemembersItsOwnZone() {
        var placement = PanelPlacement()
        placement.drop(center: CGPoint(x: 100, y: 800), among: [main, external])
        placement.drop(center: CGPoint(x: 2700, y: 700), among: [main, external])
        #expect(placement.zone(on: main.id) == .topLeft)
        #expect(placement.zone(on: external.id) == .left)
        #expect(placement.zone(on: "unknown") == .bottomRight)
    }

    @Test func missingScreenFallsBackToMainInSameZone() {
        var placement = PanelPlacement()
        placement.drop(center: CGPoint(x: 100, y: 800), among: [main, external])
        placement.drop(center: CGPoint(x: 2700, y: 700), among: [main, external])
        #expect(placement.spot(among: [main]) == PanelSpot(screen: main, zone: .left))
    }

    @Test func reconnectedScreenGetsPanelBack() {
        var placement = PanelPlacement()
        placement.drop(center: CGPoint(x: 2700, y: 700), among: [main, external])
        _ = placement.spot(among: [main])
        #expect(placement.spot(among: [main, external]) == PanelSpot(screen: external, zone: .left))
    }

    @Test(arguments: [
        (CGPoint(x: 700, y: 437), PanelZone.left),
        (CGPoint(x: 800, y: 437), .right),
        (CGPoint(x: 720, y: 400), .bottom),
        (CGPoint(x: 720, y: 500), .top),
    ])
    func dropInTheMiddleGoesToNearestEdge(center: CGPoint, zone: PanelZone) {
        var placement = PanelPlacement()
        #expect(placement.drop(center: center, among: [main])?.zone == zone)
    }

    @Test func dropOutsideEveryScreenGoesToNearestScreen() {
        var placement = PanelPlacement()
        let spot = placement.drop(center: CGPoint(x: 5000, y: 100), among: [main, external])
        #expect(spot == PanelSpot(screen: external, zone: .bottomRight))
    }

    @Test func placementSurvivesEncoding() throws {
        var placement = PanelPlacement()
        placement.drop(center: CGPoint(x: 2700, y: 700), among: [main, external])
        let data = try JSONEncoder().encode(placement)
        #expect(try JSONDecoder().decode(PanelPlacement.self, from: data) == placement)
    }

    @Test func firstLaunchIsReducedEverywhere() {
        let placement = PanelPlacement()
        #expect(placement.spot(among: [main, external])?.size == .reduced)
        #expect(placement.size(on: external.id) == .reduced)
    }

    @Test func eachScreenRemembersItsOwnSize() {
        var placement = PanelPlacement()
        placement.drop(center: CGPoint(x: 100, y: 800), among: [main, external])
        placement.resize(to: .normal, among: [main, external])
        let spot = placement.drop(center: CGPoint(x: 2700, y: 700), among: [main, external])
        #expect(spot?.size == .reduced)
        #expect(placement.size(on: main.id) == .normal)
        #expect(placement.drop(center: CGPoint(x: 100, y: 100), among: [main, external])?.size == .normal)
    }

    @Test func resizeKeepsTheZone() {
        var placement = PanelPlacement()
        placement.drop(center: CGPoint(x: 100, y: 800), among: [main, external])
        let spot = placement.resize(to: .normal, among: [main, external])
        #expect(spot == PanelSpot(screen: main, zone: .topLeft, size: .normal))
    }

    @Test func resizeOnFallbackScreenGoesWithTheMissingScreen() {
        var placement = PanelPlacement()
        placement.drop(center: CGPoint(x: 2700, y: 700), among: [main, external])
        placement.resize(to: .normal, among: [main])
        #expect(placement.size(on: external.id) == .normal)
        #expect(placement.size(on: main.id) == .reduced)
        #expect(placement.spot(among: [main])?.size == .normal)
    }

    @Test func sizesSurviveEncoding() throws {
        var placement = PanelPlacement()
        placement.resize(to: .normal, among: [main, external])
        let data = try JSONEncoder().encode(placement)
        #expect(try JSONDecoder().decode(PanelPlacement.self, from: data) == placement)
    }

    @Test func memoryFromBeforeSizesStillReads() throws {
        let data = Data(#"{"zones":{"main":"topLeft"},"screenID":"main"}"#.utf8)
        let placement = try JSONDecoder().decode(PanelPlacement.self, from: data)
        #expect(placement.spot(among: [main]) == PanelSpot(screen: main, zone: .topLeft, size: .reduced))
    }
}

struct PanelSpotTests {
    let screen = PanelScreen(id: "main", visibleFrame: CGRect(x: 100, y: 50, width: 900, height: 600))

    @Test(arguments: PanelZone.allCases, PanelSize.allCases)
    func frameStaysInsideTheVisibleFrame(zone: PanelZone, size: PanelSize) {
        let frame = PanelSpot(screen: screen, zone: zone, size: size).panelFrame
        #expect(screen.visibleFrame.contains(frame))
        #expect(frame.width == size.side && frame.height == size.side)
        #expect(PanelZone(containing: CGPoint(x: frame.midX, y: frame.midY), in: screen.visibleFrame) == zone)
    }

    @Test func reducedPanelSitsInTheCorner() {
        let frame = PanelSpot(screen: screen, zone: .bottomRight, size: .reduced).panelFrame
        #expect(frame == CGRect(x: 888, y: 50, width: 112, height: 112))
    }
}
