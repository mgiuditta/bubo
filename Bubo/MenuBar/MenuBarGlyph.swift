import AppKit

/// Bubo's menu bar icon: the brand owl drawn as a monochrome template image.
///
/// The image comes from the `MenuBarGlyph` asset, rendered at 1× and 2× from `design/brand/menu-bar-glyph.svg`
/// by `scripts/brand-icons.swift`. As a template, the system tints it for light and dark menu bars.
// ponytail: in fase 3 l'icona riflette l'Attività; qui c'è solo il gufo a riposo.
nonisolated enum MenuBarGlyph {
    /// The icon's size in points, the standard height of a menu bar image.
    static let size = CGSize(width: 18, height: 18)

    /// The spoken name of the icon.
    static let accessibilityDescription = String(localized: "Bubo")

    /// Creates the menu bar icon, or an empty template of the same size if the asset is missing.
    static func makeImage() -> NSImage {
        let image = NSImage(named: "MenuBarGlyph")?.copy() as? NSImage ?? NSImage(size: size)
        image.size = size
        image.isTemplate = true
        image.accessibilityDescription = accessibilityDescription
        return image
    }
}
