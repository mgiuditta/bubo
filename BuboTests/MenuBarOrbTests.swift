import AppKit
import Testing
@testable import Bubo

struct MenuBarOrbTests {
    let image = MenuBarOrb.makeImage()

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

        // Bitmap rows run top-down: this pixel sits in the Blob's lower right, away from the highlight.
        let body = try #require(bitmap.colorAt(x: pixels * 2 / 3, y: pixels * 2 / 3))
        let corner = try #require(bitmap.colorAt(x: 0, y: 0))
        #expect(body.alphaComponent > 0.95)
        #expect(corner.alphaComponent == 0)
    }

    @Test func outlineStaysInsideTheIcon() {
        let rect = CGRect(origin: .zero, size: MenuBarOrb.size)
        let outline = MenuBarOrb.outline(in: rect)
        #expect(rect.contains(outline.boundingBox))
        #expect(outline.contains(CGPoint(x: rect.midX, y: rect.midY)))
    }
}
