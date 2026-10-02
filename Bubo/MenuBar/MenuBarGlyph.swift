import AppKit

/// Bubo's menu bar icon: the brand owl drawn as a monochrome template image.
///
/// The image comes from the `MenuBarGlyph` asset, rendered at 1× and 2× from `design/brand/menu-bar-glyph.svg`
/// by `scripts/brand-icons.swift`. As a template, the system tints it for light and dark menu bars: no Tinta and no
/// Lume. With Sessioni in Attende te it carries a full dot at the top right; Lavora and Errore leave it at rest.
nonisolated enum MenuBarGlyph {
    /// The icon's size in points, the standard height of a menu bar image.
    static let size = CGSize(width: 18, height: 18)

    /// Where the dot of the Sessioni in Attende te sits, in the icon's bottom-up coordinates.
    static let dot = CGRect(x: 12, y: 12, width: 6, height: 6)

    /// The spoken name of the icon: Bubo, and how many Sessioni wait for the user when some do.
    static func accessibilityDescription(waiting: Int) -> String {
        waiting > 0 ? String(localized: "Bubo, \(waiting) Sessioni ti attendono") : String(localized: "Bubo")
    }

    /// Creates the menu bar icon, with the dot when `waiting` Sessioni are in Attende te; an empty template of the
    /// same size if the asset is missing.
    static func makeImage(waiting: Int = 0) -> NSImage {
        let owl = NSImage(named: "MenuBarGlyph")?.copy() as? NSImage ?? NSImage(size: size)
        owl.size = size
        let image = waiting > 0 ? NSImage(size: size, flipped: false) { bounds in
            owl.draw(in: bounds)
            // A clear ring keeps the dot apart from the owl at 1×.
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: dot.insetBy(dx: -1.5, dy: -1.5)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor.black.setFill()
            NSBezierPath(ovalIn: dot).fill()
            return true
        } : owl
        image.isTemplate = true
        image.accessibilityDescription = accessibilityDescription(waiting: waiting)
        return image
    }
}
