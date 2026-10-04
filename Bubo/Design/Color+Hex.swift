import SwiftUI

extension Color {
    /// Creates an sRGB color from a `0xRRGGBB` literal.
    ///
    /// - Parameters:
    ///   - hex: The red, green, and blue components packed as `0xRRGGBB`.
    ///   - opacity: The alpha component, from 0 to 1.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

extension Color {
    /// Creates an sRGB color from red, green, and blue components from 0 to 1, such as a Tinta's.
    ///
    /// - Parameters:
    ///   - components: The red, green, and blue components.
    ///   - opacity: The alpha component, from 0 to 1.
    init(_ components: SIMD3<Float>, opacity: Double = 1) {
        self.init(.sRGB, red: Double(components.x), green: Double(components.y), blue: Double(components.z),
                  opacity: opacity)
    }
}
