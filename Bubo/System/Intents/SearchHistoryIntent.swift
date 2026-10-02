import AppIntents

/// Where "Cerca nella cronologia" opens: the Palette of Bubo, set at launch.
protocol HistorySearching: AnyObject {
    /// Shows the Palette with an empty box, on the recent conversations.
    func searchHistory()
}

/// "Cerca nella cronologia", from Spotlight and Comandi rapidi (spec 14): brings Bubo forward and opens the Palette on
/// the conversations. It is the only way into the Cronologia from outside Bubo: no global shortcut opens it.
struct SearchHistoryIntent: AppIntent {
    static let title: LocalizedStringResource = "Cerca nella cronologia"
    static let description = IntentDescription("Apre la Palette di Bubo sulle conversazioni recenti, per cercarne una.")
    /// The Palette opens only with Bubo in front.
    static let supportedModes: IntentModes = .foreground(.immediate)

    /// Where the Palette opens, set at launch before any intent runs; tests set a stand-in.
    @MainActor static var palette: (any HistorySearching)?

    func perform() async throws -> some IntentResult {
        try await Self.open()
        return .result()
    }

    /// Opens the Palette through `palette`.
    ///
    /// - Throws: `SearchHistoryError.notReady` before launch set `palette`.
    @MainActor private static func open() throws {
        guard let palette else { throw SearchHistoryError.notReady }
        palette.searchHistory()
    }
}

/// Why "Cerca nella cronologia" did not open the Palette.
enum SearchHistoryError: Error, Equatable, CustomLocalizedStringResourceConvertible {
    /// Bubo is still starting.
    case notReady

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notReady: "Bubo si sta avviando. Riprova tra un attimo."
        }
    }
}
