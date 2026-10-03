import CoreGraphics
import SwiftUI

/// Which side of the Panel the bubble opens on: always toward the screen's center.
nonisolated enum PanelBubbleSide: Sendable, CaseIterable {
    case above, below, left, right

    /// The point of the bubble nearest to the Orb, which it grows from.
    var anchor: UnitPoint {
        switch self {
        case .above: .bottom
        case .below: .top
        case .left: .trailing
        case .right: .leading
        }
    }
}

extension PanelZone {
    /// The side the bubble opens on from this zone: top row below, bottom row and center above, left and right toward
    /// the middle.
    nonisolated var bubbleSide: PanelBubbleSide {
        switch self {
        case .topLeft, .top, .topRight: .below
        case .center, .bottomLeft, .bottom, .bottomRight: .above
        case .left: .right
        case .right: .left
        }
    }
}

/// Where the bubble goes beside the Panel.
nonisolated enum PanelBubbleLayout {
    /// How far the bubble reaches into the Panel, as a share of the Panel's side: none, so the Orb and its Varianti
    /// stay in sight beside the answer.
    static let overlapRatio: CGFloat = 0
    /// The bubble's tallest share of the visible frame; past it, the bubble scrolls.
    static let heightRatio: CGFloat = 0.5
    /// The space the bubble keeps from the visible frame's edges.
    static let edgeMargin: CGFloat = 16

    /// Returns the bubble's greatest height on a screen with `visibleFrame`, at both Panel sizes.
    static func maxHeight(in visibleFrame: CGRect) -> CGFloat {
        (visibleFrame.height * heightRatio).rounded(.down)
    }

    /// Returns the bubble's frame for content of `size`, beside a Panel at `panelFrame` in `zone`, inside
    /// `visibleFrame`.
    ///
    /// Opening above or below, the bubble lines up with the Panel's outer edge in the corners and with its middle in the
    /// center column; opening left or right, with the Panel's middle.
    static func frame(ofSize size: CGSize, besidePanel panelFrame: CGRect, in zone: PanelZone,
                      visibleFrame: CGRect) -> CGRect {
        let overlap = panelFrame.width * overlapRatio
        var origin: CGPoint
        switch zone.bubbleSide {
        case .above, .below:
            let x = switch zone {
            case .topLeft, .bottomLeft: panelFrame.minX
            case .topRight, .bottomRight: panelFrame.maxX - size.width
            default: panelFrame.midX - size.width / 2
            }
            let y = zone.bubbleSide == .above ? panelFrame.maxY - overlap : panelFrame.minY + overlap - size.height
            origin = CGPoint(x: x, y: y)
        case .left:
            origin = CGPoint(x: panelFrame.minX + overlap - size.width, y: panelFrame.midY - size.height / 2)
        case .right:
            origin = CGPoint(x: panelFrame.maxX - overlap, y: panelFrame.midY - size.height / 2)
        }
        let inside = visibleFrame.insetBy(dx: edgeMargin, dy: edgeMargin)
        origin.x = min(max(origin.x, inside.minX), inside.maxX - size.width)
        origin.y = min(max(origin.y, inside.minY), inside.maxY - size.height)
        return CGRect(origin: origin, size: size)
    }
}
