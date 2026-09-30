import AppKit

/// The miniature Orb shown as Bubo's menu bar icon: a still Blob silhouette drawn as a template image.
///
/// The image is vector-drawn on demand, so it stays sharp at any backing scale, and as a template
/// the system tints it for light and dark menu bars. It is static: the menu bar never runs the Metal renderer.
// ponytail: in fase 3 l'icona riflette l'Attività; qui c'è solo il Blob a riposo.
nonisolated enum MenuBarOrb {
    /// The icon's size in points, the standard height of a menu bar image.
    static let size = CGSize(width: 18, height: 18)

    /// The spoken name of the icon.
    static let accessibilityDescription = String(localized: "Bubo")

    /// Creates the menu bar icon.
    static func makeImage() -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            draw(in: rect)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = accessibilityDescription
        return image
    }

    /// The Blob's outline, a circle gently deformed by two low harmonics like the resting Orb.
    ///
    /// - Parameter rect: The square the Blob fits in, with a small margin.
    static func outline(in rect: CGRect) -> CGPath {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) * 0.4
        let steps = 72
        let path = CGMutablePath()
        for step in 0..<steps {
            let angle = Double(step) / Double(steps) * 2 * .pi
            let wobble = 1 + 0.06 * sin(2 * angle + 0.6) + 0.035 * sin(3 * angle + 2.1)
            let point = CGPoint(
                x: center.x + radius * wobble * cos(angle),
                y: center.y + radius * wobble * sin(angle)
            )
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    /// Fills the Blob and cuts a soft highlight into its upper left, hinting at the Orb's volume.
    private static func draw(in rect: CGRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.addPath(outline(in: rect))
        context.setFillColor(NSColor.black.cgColor)
        context.fillPath()

        let highlight = CGRect(
            x: rect.minX + rect.width * 0.3,
            y: rect.minY + rect.height * 0.55,
            width: rect.width * 0.22,
            height: rect.height * 0.16
        )
        context.setBlendMode(.destinationOut)
        context.setFillColor(NSColor.black.withAlphaComponent(0.55).cgColor)
        context.fillEllipse(in: highlight)
    }
}
