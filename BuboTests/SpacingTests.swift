import CoreGraphics
import Testing
@testable import Bubo

/// The spacing scale of the brand kit (design system, Spaziatura).
struct SpacingTests {
    @Test func theScaleGoesFromFourToFortyEight() {
        let scale = [Spacing.xxs, Spacing.xs, Spacing.s, Spacing.m, Spacing.l, Spacing.xl, Spacing.xxl]
        #expect(scale == [4, 8, 12, 16, 24, 32, 48])
    }

    @Test func sidebarRowsAreAtLeast36PointsHigh() {
        #expect(Spacing.sidebarRowMinHeight == 36)
    }

    @Test func conversationsAreReadAt720PointsAtMost() {
        #expect(Spacing.readingWidth == 720)
    }
}
