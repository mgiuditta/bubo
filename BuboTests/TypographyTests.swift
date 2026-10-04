import CoreText
import SwiftUI
import Testing
@testable import Bubo

/// The type roles of the brand kit (design system, Tipografia), resolved as SwiftUI draws them.
struct TypographyTests {
    private let context = EnvironmentValues().fontResolutionContext

    @Test func displayIsNewsreaderMediumAt34() {
        let display = Font.buboDisplay.resolve(in: context)
        #expect(display.pointSize == 34)
        #expect(CTFontCopyPostScriptName(display.ctFont) as String == "NewsreaderRoman-Medium")
    }

    @Test func titleIsSemiboldAt22() throws {
        let title = Font.buboTitle.resolve(in: context)
        #expect(title.pointSize == 22)
        let traits = CTFontCopyTraits(title.ctFont) as? [CFString: Any]
        let weight = try #require(traits?[kCTFontWeightTrait] as? Double)
        // Semibold is 0.3 on the CoreText scale; the resolved font carries it as a Float.
        #expect(abs(weight - 0.3) < 0.001)
    }

    @Test(arguments: [(Font.buboBody, 15.0), (Font.buboInterface, 13.0)])
    func textRolesUseTheSystemFace(font: Font, size: CGFloat) {
        let resolved = font.resolve(in: context)
        #expect(resolved.pointSize == size)
        #expect(!resolved.isMonospaced)
    }

    @Test func dataIsMonospacedAt12() {
        let data = Font.buboData.resolve(in: context)
        #expect(data.pointSize == 12)
        #expect(data.isMonospaced)
    }

    @Test func titlesAreSlightlyTight() {
        #expect(Typography.titleTracking == -0.2)
    }
}
