import AppKit
import Testing
@testable import Bubo

/// The typefaces in `Resources/Fonts`, registered by the system through `ATSApplicationFontsPath`.
struct BundledFontsTests {
    @Test func theAppAsksTheSystemToRegisterItsFontsFolder() {
        #expect(Bundle.main.object(forInfoDictionaryKey: "ATSApplicationFontsPath") as? String == "Fonts")
    }

    @Test func newsreaderMediumResolves() {
        #expect(NSFont(name: "NewsreaderRoman-Medium", size: 34) != nil)
    }

    @Test(arguments: ["Newsreader", "Unbounded", "Manrope", "JetBrains Mono"])
    func everyBundledFamilyIsAvailable(family: String) {
        #expect(NSFontManager.shared.availableMembers(ofFontFamily: family) != nil)
    }
}
