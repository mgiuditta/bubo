import CoreGraphics

/// The fixed circle around the Orb that takes the pointer; elsewhere clicks reach the windows below.
///
/// It is a circle and not the Orb's silhouette, which changes during a Morph.
nonisolated enum PanelClickCircle {
    /// Returns whether `point` falls in the circle of a Panel of `size` with frame `panelFrame`, border included.
    ///
    /// The circle's radius is ``PanelSize/clickRadius``: the Blob with its noise and some margin, well inside the halo.
    static func contains(_ point: CGPoint, inPanel panelFrame: CGRect, of size: PanelSize) -> Bool {
        let dx = point.x - panelFrame.midX
        let dy = point.y - panelFrame.midY
        return dx * dx + dy * dy <= size.clickRadius * size.clickRadius
    }
}

/// A press on the Orb, which stays a click until the pointer moves far enough to make it a drag.
nonisolated struct PanelPress: Sendable {
    /// How far the pointer must move, in points, to turn a click into a drag.
    static let dragThreshold: CGFloat = 4

    /// Where the press started.
    let start: CGPoint
    /// Whether the press has become a drag; once it has, it stays one.
    private(set) var isDrag = false

    /// Creates a press that started at `start`.
    init(at start: CGPoint) {
        self.start = start
    }

    /// Follows the pointer to `point`, turning the press into a drag past the threshold.
    mutating func move(to point: CGPoint) {
        let dx = point.x - start.x
        let dy = point.y - start.y
        if dx * dx + dy * dy >= Self.dragThreshold * Self.dragThreshold { isDrag = true }
    }
}
