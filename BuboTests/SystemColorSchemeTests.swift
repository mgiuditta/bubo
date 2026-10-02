import SwiftUI
import Testing
@testable import Bubo

/// The Anteprima follows the system's appearance, read from `AppleInterfaceStyle`, not the HUD's forced dark.
struct SystemColorSchemeTests {
    @Test(arguments: [
        (String?.none, ColorScheme.light),
        ("Dark", .dark),
        ("Light", .light),
    ])
    func interfaceStyleGivesTheScheme(style: String?, expected: ColorScheme) {
        #expect(ColorScheme(interfaceStyle: style) == expected)
    }
}
