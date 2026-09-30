import CoreGraphics

/// One of the nine zones of the 3×3 grid the Panel snaps to on a screen's visible frame.
///
/// In phase 3 the zone tells which way bubbles and cards open: toward the center.
nonisolated enum PanelZone: String, CaseIterable, Codable, Sendable {
    case topLeft, top, topRight
    case left, center, right
    case bottomLeft, bottom, bottomRight

    /// Creates the zone of `visibleFrame` that contains `point`.
    ///
    /// A point on an inner line belongs to the zone right of it or above it; a point outside the frame
    /// belongs to the nearest zone.
    init(containing point: CGPoint, in visibleFrame: CGRect) {
        let column = Self.third(of: point.x - visibleFrame.minX, across: visibleFrame.width)
        let row = Self.third(of: point.y - visibleFrame.minY, across: visibleFrame.height)
        self = Self.grid[2 - row][column]
    }

    /// Returns the origin that puts a Panel of `side` points in this zone of `visibleFrame`, flush with its edges.
    func panelOrigin(side: CGFloat, in visibleFrame: CGRect) -> CGPoint {
        let (row, column) = Self.position(of: self)
        let x = [visibleFrame.minX, visibleFrame.midX - side / 2, visibleFrame.maxX - side][column]
        let y = [visibleFrame.maxY - side, visibleFrame.midY - side / 2, visibleFrame.minY][row]
        return CGPoint(x: x, y: y)
    }

    /// The zones row by row, top to bottom.
    private static let grid: [[PanelZone]] = [
        [.topLeft, .top, .topRight],
        [.left, .center, .right],
        [.bottomLeft, .bottom, .bottomRight],
    ]

    private static func third(of offset: CGFloat, across length: CGFloat) -> Int {
        guard length > 0 else { return 0 }
        return min(max(Int((offset / (length / 3)).rounded(.down)), 0), 2)
    }

    private static func position(of zone: PanelZone) -> (row: Int, column: Int) {
        let index = allCases.firstIndex(of: zone)!
        return (index / 3, index % 3)
    }
}

/// A screen as the Panel sees it: a stable identity and the area free of menu bar and Dock.
nonisolated struct PanelScreen: Equatable, Sendable {
    /// An identifier that survives relaunches and reconnections.
    var id: String
    /// The screen's visible frame, in global coordinates.
    var visibleFrame: CGRect
}

/// Where the Panel sits: a screen and a zone on it.
nonisolated struct PanelSpot: Equatable, Sendable {
    var screen: PanelScreen
    var zone: PanelZone

    /// Returns the origin of a Panel of `side` points at this spot.
    func panelOrigin(side: CGFloat) -> CGPoint {
        zone.panelOrigin(side: side, in: screen.visibleFrame)
    }
}

/// The Panel's position memory: the zone chosen on each screen and the screen it was last dropped on.
nonisolated struct PanelPlacement: Equatable, Codable, Sendable {
    /// The zone of a screen the Panel has never been dropped on.
    static let defaultZone = PanelZone.bottomRight

    /// The zone remembered for each screen, by screen identifier.
    private(set) var zones: [String: PanelZone] = [:]
    /// The identifier of the screen the Panel was last dropped on.
    private(set) var screenID: String?

    /// Returns the zone remembered for the screen with `screenID`, or the default zone.
    func zone(on screenID: String) -> PanelZone {
        zones[screenID] ?? Self.defaultZone
    }

    /// Returns where the Panel goes among `screens`, the first being the main screen.
    ///
    /// If the last screen is missing, the Panel goes on the main screen in the same zone,
    /// and comes back when that screen returns.
    func spot(among screens: [PanelScreen]) -> PanelSpot? {
        if let screen = screens.first(where: { $0.id == screenID }) {
            return PanelSpot(screen: screen, zone: zone(on: screen.id))
        }
        guard let main = screens.first else { return nil }
        return PanelSpot(screen: main, zone: zone(on: screenID ?? main.id))
    }

    /// Snaps a Panel released with its center at `center` and remembers the result.
    ///
    /// The Panel goes to the screen under `center`, or the nearest one.
    /// - Returns: The spot the Panel snaps to, or `nil` if there are no screens.
    @discardableResult
    mutating func drop(center: CGPoint, among screens: [PanelScreen]) -> PanelSpot? {
        let screen = screens.first { $0.visibleFrame.contains(center) }
            ?? screens.min { distance(from: center, to: $0.visibleFrame) < distance(from: center, to: $1.visibleFrame) }
        guard let screen else { return nil }
        let zone = PanelZone(containing: center, in: screen.visibleFrame)
        zones[screen.id] = zone
        screenID = screen.id
        return PanelSpot(screen: screen, zone: zone)
    }

    private func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }
}
