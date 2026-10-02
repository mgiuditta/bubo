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

    /// Begins the interval `interval`; end it with `endInterval(_:_:)`, when it spans more than one call.
    static func beginInterval(_ interval: Signpost) -> OSSignpostIntervalState {
        signposter.beginInterval(interval.name, id: signposter.makeSignpostID())
    }

    /// Ends the interval `interval` begun with `state`.
    static func endInterval(_ interval: Signpost, _ state: OSSignpostIntervalState) {
        signposter.endInterval(interval.name, state)
    }

    /// Emits `HUD interattivo` the first time it is called, and never again.
    ///
    /// The end of launch: later HUD appearances are not launches. MetricKit ends its extended launch here too.
    static func markHUDInteractive() {
        guard !hasMarkedHUDInteractive else { return }
        hasMarkedHUDInteractive = true
        emit(.hudInteractive)
        MetricsCollector.shared.finishLaunch()
    }
}

/// A signpost name from the closed catalog.
enum Signpost {
    /// The HUD has drawn and the main thread accepts input: launch is over.
    case hudInteractive
    /// Interval: `LaunchSequence` starting the work deferred until `hudInteractive`.
    case deferredLaunch
    /// Interval: finding `claude` and reading its version and login, after `hudInteractive`.
    case claudeDetection
    /// Interval: listing the Cronologia CLI through the bridge.
    case cliHistory
    /// Interval: from choosing another Vista delle Sessioni to the HUD laid out with it.
    case vistaSwitch
    /// Interval: reading a Sessione's changes from git for the revisione.
    case reviewDiff
    /// Interval: working out with `git merge-tree` what Fondi would do, before the click.
    case mergePreview
    /// Interval: from opening a Galassia to its first image with stars.
    case galaxyFirstImage
    /// The first token of the first Sessione's answer: the onboarding is over.
    case onboardingFirstToken
    /// Interval: from sending a Richiesta to the classifier's decision, when the Morph towards its Variante starts.
    case intakeDecision
    /// Interval: from letting go of push-to-talk to the final text of what was said.
    case voiceFinalText
    /// Interval: from the first text of an answer asked by voice to the first audio of its Sintesi parlata.
    case voiceFirstAudio
    /// Interval: from the interruption of the Sintesi parlata, by the shortcut or Esc, to the audio stopped.
    case voiceInterruption
    /// Interval: compiling the pipeline of a Forma on its first request (ADR 0010).
    case formaCompilation
    /// Interval: from opening the Plugin window to its first snapshot, read from the files.
    case pluginsFirstDraw

    /// The name shown in Instruments.
    var name: StaticString {
        switch self {
        case .hudInteractive: "HUD interattivo"
        case .deferredLaunch: "Avvio differito"
        case .claudeDetection: "Rilevamento claude"
        case .cliHistory: "Cronologia CLI"
        case .vistaSwitch: "Cambio vista"
        case .reviewDiff: "Diff della revisione"
        case .mergePreview: "Conflitti previsti"
        case .galaxyFirstImage: "Prima immagine della Galassia"
        case .onboardingFirstToken: "Primo token onboarding"
        case .intakeDecision: "Decisione della Richiesta"
        case .voiceFinalText: "Testo finale della voce"
        case .voiceFirstAudio: "Primo audio della Sintesi parlata"
        case .voiceInterruption: "Interruzione della voce"
        case .formaCompilation: "Compilazione Forma"
        case .pluginsFirstDraw: "Primo disegno dei Plugin"
        }
    }
}
