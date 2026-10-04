import SwiftUI
import Testing
@testable import Bubo

/// The Liquid Glass capsule of quiet actions such as Impostazioni.
@MainActor
struct GlassCapsuleButtonTests {
    @Test func theCapsuleIs32PointsHigh() throws {
        let renderer = ImageRenderer(content: GlassCapsuleButton("Impostazioni", systemImage: "gearshape") {})
        let image = try #require(renderer.nsImage)
        #expect(image.size.height == GlassCapsuleButton.height)
        #expect(GlassCapsuleButton.height == 32)
    }
}
