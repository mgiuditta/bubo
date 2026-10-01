import OSLog

/// Bubo's one signposter and the closed catalog of its signpost names.
///
/// Everything lands in the Points of Interest track of Instruments and can be
/// measured with `XCTOSSignpostMetric`. Features add their names to `Signpost`.
enum Signposts {
    /// The signposter of the whole app, in the `pointsOfInterest` category.
    static let signposter = OSSignposter(subsystem: "com.mgiuditta.bubo", category: .pointsOfInterest)

    private static var hasMarkedHUDInteractive = false

    /// Emits a point-in-time signpost.
    static func emit(_ event: Signpost) {
        signposter.emitEvent(event.name)
    }

    /// Runs `work` inside the interval `interval` and returns its result.
    static func measure<T>(_ interval: Signpost, around work: () async throws -> T) async rethrows -> T {
        let state = signposter.beginInterval(interval.name, id: signposter.makeSignpostID())
        defer { signposter.endInterval(interval.name, state) }
        return try await work()
    }

    /// Emits `HUD interattivo` the first time it is called, and never again.
    ///
    /// The end of launch: later HUD appearances are not launches.
    static func markHUDInteractive() {
        guard !hasMarkedHUDInteractive else { return }
        hasMarkedHUDInteractive = true
        emit(.hudInteractive)
    }
}

/// A signpost name from the closed catalog.
enum Signpost {
    /// The HUD has drawn and the main thread accepts input: launch is over.
    case hudInteractive
    /// Interval: finding `claude` and reading its version and login, after `hudInteractive`.
    case claudeDetection
    /// Interval: listing the Cronologia CLI through the bridge.
    case cliHistory

    /// The name shown in Instruments.
    var name: StaticString {
        switch self {
        case .hudInteractive: "HUD interattivo"
        case .claudeDetection: "Rilevamento claude"
        case .cliHistory: "Cronologia CLI"
        }
    }
}
