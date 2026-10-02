import Foundation

/// The turns of the Cronologia CLI the Costi window shows, read again each time the window opens.
///
/// They live here, never in the CostLedger, so the Budget never counts them (spec 18).
@Observable
final class CLIHistoryCosts {
    /// The turns read last, oldest first.
    private(set) var entries: [CostLedger.Entry] = []
    /// Whether a reading is under way.
    private(set) var isReading = false

    /// Creates the turns read by the reader `makeReader` returns, made again at each reading so it follows the
    /// setting that copies the Cronologia CLI.
    init(makeReader: @escaping () -> CLIHistoryReader) {
        self.makeReader = makeReader
    }

    @ObservationIgnored private let makeReader: () -> CLIHistoryReader
    @ObservationIgnored private var reading: Task<Void, Never>?

    /// Reads the turns again, away from the main actor, in place of a reading still under way.
    func reload() {
        reading?.cancel()
        let reader = makeReader()
        isReading = true
        reading = Task {
            let entries = await reader.entries()
            guard !Task.isCancelled else { return }
            self.entries = entries
            isReading = false
        }
    }

    /// The reader of the user's Cronologia CLI: Bubo's copy when the setting keeps it, and `~/.claude/projects`.
    nonisolated static func userReader() -> CLIHistoryReader {
        let keepsCopy = UserDefaults.standard.bool(forKey: ConversationStore.keepsCLIHistoryKey)
        return CLIHistoryReader(database: keepsCopy ? try? ConversationStore.defaultFile() : nil,
                                projects: CLIHistoryReader.userProjects, prices: .bundled)
    }
}
