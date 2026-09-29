import CoreText
import Foundation
import OSLog

/// Registers the typefaces bundled with the app for this process only.
enum FontRegistry {
    private static let logger = Logger(subsystem: "com.mgiuditta.bubo", category: "fonts")

    /// Registers every `.ttf` in the bundle's `Fonts` folder.
    ///
    /// Missing or broken files are logged and skipped, so text falls back to
    /// the system font instead of the app failing to launch.
    static func registerBundledFonts() {
        guard let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts"), !urls.isEmpty else {
            logger.error("No bundled fonts found")
            return
        }
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, true) { errors, _ in
            for error in errors as? [CFError] ?? [] {
                logger.error("Font registration failed: \(error.localizedDescription, privacy: .public)")
            }
            return true
        }
    }
}
