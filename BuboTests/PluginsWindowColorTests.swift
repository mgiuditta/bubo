import Foundation
import Testing

/// The Plugin window keeps Lume for what waits for the user and uses the design system's tokens, never the
/// system's colors (design system, review of #206).
struct PluginsWindowColorTests {
    @Test func thePluginsWindowUsesNoLumeAndNoSystemColors() throws {
        let folder = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../Bubo/Plugins").standardized
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        #expect(files.count > 10)
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            for match in source.matches(of: /Palette\.attention|\.(red|yellow|orange|green|blue)\b|Color\(red:/) {
                Issue.record("\(file.lastPathComponent) usa \(match.output.0)")
            }
        }
    }
}
