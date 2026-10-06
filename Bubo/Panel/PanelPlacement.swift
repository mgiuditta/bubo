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

/// One of the Panel's two fixed sizes: there is no free resizing.
nonisolated enum PanelSize: String, CaseIterable, Codable, Sendable {
    /// The Panel of #25, 240 pt.
    case normal
    /// The small chat in a corner, 112 pt, with an Orb of about 62 pt.
    case reduced

    /// The Panel's side, in points.
    var side: CGFloat {
        switch self {
        case .normal: 240
        case .reduced: 112
        }
    }

    /// The drawable's pixels per point: below Retina for the normal Panel to save GPU, Retina for the reduced one,
    /// which has 2.6 times fewer pixels anyway.
    var renderScale: CGFloat {
        switch self {
        case .normal: 1.5
        case .reduced: 2
        }
    }

    /// The radius of the click circle, in points: the same share of the side, 80 of 240.
    var clickRadius: CGFloat {
        switch self {
        case .normal: 80
        case .reduced: 37
        }
    }

    /// The other size, for the menu item and the VoiceOver action that switch between the two.
    var toggled: PanelSize {
        self == .normal ? .reduced : .normal
    }
}

/// A screen as the Panel sees it: a stable identity and the area free of menu bar and Dock.
nonisolated struct PanelScreen: Equatable, Sendable {
    /// An identifier that survives relaunches and reconnections.
    var id: String
    /// The screen's visible frame, in global coordinates.
    var visibleFrame: CGRect
}

/// Where the Panel sits: a screen, a zone on it, and the size it has there.
nonisolated struct PanelSpot: Equatable, Sendable {
    var screen: PanelScreen
    var zone: PanelZone
    var size = PanelPlacement.defaultSize

    /// The Panel's frame at this spot, flush with the zone's edges.
    var panelFrame: CGRect {
        CGRect(origin: zone.panelOrigin(side: size.side, in: screen.visibleFrame),
               size: CGSize(width: size.side, height: size.side))
    }
}

/// The Panel's position memory: the zone and the size chosen on each screen and the screen it was last dropped on.
nonisolated struct PanelPlacement: Equatable, Codable, Sendable {
    /// The zone of a screen the Panel has never been dropped on.
    static let defaultZone = PanelZone.bottomRight
    /// The size on a screen where the user has never chosen one: the small chat in a corner.
    static let defaultSize = PanelSize.reduced

    /// The zone remembered for each screen, by screen identifier.
    private(set) var zones: [String: PanelZone] = [:]
    /// The size remembered for each screen, by screen identifier.
    private(set) var sizes: [String: PanelSize] = [:]
    /// The identifier of the screen the Panel was last dropped on.
    private(set) var screenID: String?

    /// Creates an empty memory: every screen gets the default zone and size.
    init() {}

    /// Creates the memory saved by this or an earlier version, which kept no sizes.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        zones = try container.decodeIfPresent([String: PanelZone].self, forKey: .zones) ?? [:]
        sizes = try container.decodeIfPresent([String: PanelSize].self, forKey: .sizes) ?? [:]
        screenID = try container.decodeIfPresent(String.self, forKey: .screenID)
    }

    /// Returns the zone remembered for the screen with `screenID`, or the default zone; never the center, which an
    /// older version could remember.
    func zone(on screenID: String) -> PanelZone {
        zones[screenID].flatMap { $0 == .center ? nil : $0 } ?? Self.defaultZone
    }

    /// Returns the size remembered for the screen with `screenID`, or the default size.
    func size(on screenID: String) -> PanelSize {
        sizes[screenID] ?? Self.defaultSize
    }

    /// Returns where the Panel goes among `screens`, the first being the main screen.
    ///
    /// If the last screen is missing, the Panel goes on the main screen in the same zone,
    /// and comes back when that screen returns.
    func spot(among screens: [PanelScreen]) -> PanelSpot? {
        if let screen = screens.first(where: { $0.id == screenID }) {
            return PanelSpot(screen: screen, zone: zone(on: screen.id), size: size(on: screen.id))
        }
        guard let main = screens.first else { return nil }
        let id = screenID ?? main.id
        return PanelSpot(screen: main, zone: zone(on: id), size: size(on: id))
    }

    /// Gives the Panel `size` where it stands among `screens`, the first being the main screen, and remembers it.
    ///
    /// The size goes with the screen whose memory the Panel follows: the last one it was dropped on even while it
    /// stands in for it on the main screen.
    /// - Returns: The spot with the new size, or `nil` if there are no screens.
    @discardableResult
    mutating func resize(to size: PanelSize, among screens: [PanelScreen]) -> PanelSpot? {
        guard let id = screenID ?? screens.first?.id else { return nil }
        sizes[id] = size
        return spot(among: screens)
    }

    /// Snaps a Panel released with its center at `center` and remembers the result.
    ///
    /// The Panel goes to the screen under `center`, or the nearest one, with the size remembered there. It never
    /// stays in the middle of the screen: dropped there, it goes to the nearest edge.
    /// - Returns: The spot the Panel snaps to, or `nil` if there are no screens.
    @discardableResult
    mutating func drop(center: CGPoint, among screens: [PanelScreen]) -> PanelSpot? {
        let screen = screens.first { $0.visibleFrame.contains(center) }
            ?? screens.min { distance(from: center, to: $0.visibleFrame) < distance(from: center, to: $1.visibleFrame) }
        guard let screen else { return nil }
        var zone = PanelZone(containing: center, in: screen.visibleFrame)
        if zone == .center { zone = Self.nearestEdge(to: center, in: screen.visibleFrame) }
        zones[screen.id] = zone
        screenID = screen.id
        return PanelSpot(screen: screen, zone: zone, size: size(on: screen.id))
    }

    /// The edge zone of `frame` nearest to `point`, measured as a share of the frame's width and height.
    private static func nearestEdge(to point: CGPoint, in frame: CGRect) -> PanelZone {
        let dx = (point.x - frame.midX) / frame.width
        let dy = (point.y - frame.midY) / frame.height
        if abs(dx) > abs(dy) { return dx < 0 ? .left : .right }
        return dy < 0 ? .bottom : .top
    }

    private func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }
}
