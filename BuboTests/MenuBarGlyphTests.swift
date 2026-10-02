import AppKit
import Testing
@testable import Bubo

struct MenuBarGlyphTests {
    let image = MenuBarGlyph.makeImage()

    @Test func isAMenuBarSizedTemplate() {
        #expect(image.size == CGSize(width: 18, height: 18))
        // A template image is tinted by the system, so it reads in both light and dark menu bars.
        #expect(image.isTemplate)
    }

    @Test func hasAnAccessibilityDescription() {
        #expect(image.accessibilityDescription?.isEmpty == false)
    }

    @Test(arguments: [1, 2, 3])
    func rendersAtBackingScale(scale: Int) throws {
        let pixels = 18 * scale
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        bitmap.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()

        // Bitmap rows run top-down. The head is solid below the eyes, an eye is cut out, a corner is empty.
        let point = { (x: Double, y: Double) in (Int(x * Double(scale)), Int(y * Double(scale))) }
        let (headX, headY) = point(9, 15.6)
        let (eyeX, eyeY) = point(6, 10)
        let head = try #require(bitmap.colorAt(x: headX, y: headY))
        let eye = try #require(bitmap.colorAt(x: eyeX, y: eyeY))
        let corner = try #require(bitmap.colorAt(x: 0, y: pixels - 1))
        #expect(head.alphaComponent > 0.95)
        #expect(eye.alphaComponent < 0.05)
        #expect(corner.alphaComponent == 0)
    }

    @Test func waitingSessionsAddAFullDotAndAClearRing() throws {
        let waiting = MenuBarGlyph.makeImage(waiting: 2)
        #expect(waiting.isTemplate)
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 36, pixelsHigh: 36,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        bitmap.size = waiting.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        waiting.draw(in: CGRect(origin: .zero, size: waiting.size))
        NSGraphicsContext.restoreGraphicsState()

        // Bitmap rows run top-down: the dot's centre is at (15, 3) points, the ring just left of it.
        let dot = try #require(bitmap.colorAt(x: 30, y: 6))
        let ring = try #require(bitmap.colorAt(x: 22, y: 6))
        #expect(dot.alphaComponent > 0.95)
        #expect(ring.alphaComponent < 0.05)
    }

    @Test func descriptionSaysHowManySessioniWait() {
        #expect(MenuBarGlyph.makeImage().accessibilityDescription == String(localized: "Bubo"))
        #expect(MenuBarGlyph.makeImage(waiting: 2).accessibilityDescription
                == String(localized: "Bubo, \(2) Sessioni ti attendono"))
    }
}
