import AppKit

/// The Dock icon's count of the Sessioni in Attende te, and its bounce.
enum DockBadge {
    /// Shows `count` on the Dock icon; nothing when it is 0.
    static func show(_ count: Int) {
        NSApp.dockTile.badgeLabel = count > 0 ? count.formatted() : nil
    }

    /// Bounces the Dock icon once, without bringing Bubo to the front.
    static func bounce() {
        NSApp.requestUserAttention(.informationalRequest)
    }
}
