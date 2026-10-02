import AppIntents
import Testing
@testable import Bubo

@MainActor
@Suite(.serialized)
struct SearchHistoryIntentTests {
    /// Counts the times "Cerca nella cronologia" opens the Palette, in place of Bubo.
    @MainActor final class RecordingPalette: HistorySearching {
        private(set) var openings = 0

        func searchHistory() { openings += 1 }
    }

    let palette = RecordingPalette()

    init() {
        SearchHistoryIntent.palette = palette
    }

    @Test func opensThePalette() async throws {
        _ = try await SearchHistoryIntent().perform()

        #expect(palette.openings == 1)
    }

    @Test func bringsBuboForward() {
        #expect(SearchHistoryIntent.supportedModes == .foreground(.immediate))
    }

    @Test func beforeLaunchItSaysBuboIsStarting() async {
        SearchHistoryIntent.palette = nil
        await #expect(throws: SearchHistoryError.notReady) {
            _ = try await SearchHistoryIntent().perform()
        }
    }
}
