import CoreGraphics

extension PanelZone {
    /// The side the status pill sits on from this zone: beside the Orb toward the screen's center, above or below it
    /// in the middle column.
    nonisolated var statusSide: PanelBubbleSide {
        switch self {
        case .topLeft, .left, .bottomLeft: .right
        case .topRight, .right, .bottomRight: .left
        case .top: .below
        case .center, .bottom: .above
        }
    }
}

/// Where the status pill goes beside the Panel.
nonisolated enum PanelStatusLayout {
    /// The pill's height, in points.
    static let height: CGFloat = 24
    /// How far the pill reaches into the Panel's transparent margin, as a share of the Panel's side: about 17 pt of
    /// 112, outside the click circle, a few points from the Orb.
    static let overlapRatio: CGFloat = 0.15

    /// Returns the pill's frame for content of `size`, beside a Panel at `panelFrame` in `zone`, inside
    /// `visibleFrame`; it is centered on the Orb along the side it sits on.
    static func frame(ofSize size: CGSize, besidePanel panelFrame: CGRect, in zone: PanelZone,
                      visibleFrame: CGRect) -> CGRect {
        let overlap = panelFrame.width * overlapRatio
        var origin = switch zone.statusSide {
        case .left: CGPoint(x: panelFrame.minX + overlap - size.width, y: panelFrame.midY - size.height / 2)
        case .right: CGPoint(x: panelFrame.maxX - overlap, y: panelFrame.midY - size.height / 2)
        case .above: CGPoint(x: panelFrame.midX - size.width / 2, y: panelFrame.maxY - overlap)
        case .below: CGPoint(x: panelFrame.midX - size.width / 2, y: panelFrame.minY + overlap - size.height)
        }
        origin.x = min(max(origin.x, visibleFrame.minX), visibleFrame.maxX - size.width)
        origin.y = min(max(origin.y, visibleFrame.minY), visibleFrame.maxY - size.height)
        return CGRect(origin: origin, size: size)
    }
}
