import Foundation
import Testing
@testable import Bubo

@MainActor
@Suite(.serialized)
struct OpenGalaxyIntentTests {
    /// Records the Galassie "Apri Galassia" opens, in place of the Galassia windows.
    @MainActor final class RecordingOpener: GalaxyOpening {
        private(set) var shown: [URL] = []

        func show(_ project: URL) { shown.append(project) }
    }

    let opener = RecordingOpener()

    init() {
        OpenGalaxyIntent.galaxies = opener
    }

    func intent(on project: URL) -> OpenGalaxyIntent {
        let intent = OpenGalaxyIntent()
        intent.target = ProjectEntity(folder: project)
        return intent
    }

    @Test func opensTheGalassiaOfTheProgetto() async throws {
        let folder = FileManager.default.temporaryDirectory
        _ = try await intent(on: folder).perform()

        #expect(opener.shown.map(\.standardizedFileURL) == [folder.standardizedFileURL])
    }

    @Test func aProgettoThatIsGoneOpensNothing() async {
        let gone = URL(filePath: "/tmp/bubo-sparito-\(UUID().uuidString)", directoryHint: .isDirectory)
        await #expect(throws: OpenGalaxyError.projectMissing(gone.lastPathComponent)) {
            _ = try await intent(on: gone).perform()
        }

        #expect(opener.shown.isEmpty)
    }

    @Test func beforeLaunchItSaysBuboIsStarting() async {
        OpenGalaxyIntent.galaxies = nil
        await #expect(throws: OpenGalaxyError.notReady) {
            _ = try await intent(on: FileManager.default.temporaryDirectory).perform()
        }
    }
}
