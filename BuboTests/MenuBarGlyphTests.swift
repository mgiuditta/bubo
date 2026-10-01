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
}
