import Foundation
import os

/// The one road from an ingresso to the engine (spec 09, Pipeline unica degli ingressi); today the prompt scritto enters it.
///
/// At submit the Orb enters Pensiero at once with the Tinta of the expected provider; the classifier's decision asks for the
/// Morph towards the Variante, or the Blob when it is uncertain, and comes with the router's choice of model and effort; the first token turns the Orb to Lavora. The Regia del
/// Morph runs a started Morph to the end, whatever comes after.
@Observable
final class IntakePipeline {
    /// What the Orb shows of the last Richiesta: its Variante and its Tinta.
    struct Forecast: Equatable {
        /// The Variante the Orb morphs into; `nil` is the Blob.
        let variante: Variante?
        /// The provider whose Tinta the Orb takes; `nil` for the neutral Tinta.
        let provider: Provider?
    }

    /// One Richiesta through the pipeline; a newer one makes it stale, and a stale one no longer moves the Orb.
    struct Submission: Equatable {
        fileprivate let id: Int
        /// The classifier's verdict; `nil` when no Catalogo could be read.
        let classification: RequestClassification?
        /// The router's decision, taken before the Morph starts.
        let route: Route
    }

    /// What is read under the Orb while a Richiesta is under way; `nil` before its classification and after its answer.
    private(set) var forecast: Forecast?

    /// Creates the pipeline that drives `orb`.
    ///
    /// - Parameters:
    ///   - onDevice: Apple's model on the Mac, which measures what a Richiesta carries for the router.
    ///   - makeClassifier: Builds the classifier on the first Richiesta, so launch does not pay for it; `nil` when it
    ///     cannot be built, and then the Orb keeps its Forma.
    init(orb: OrbControls = .shared, onDevice: OnDeviceModel = OnDeviceModel(),
         makeClassifier: @escaping () -> RequestClassifier? = IntakePipeline.bundledClassifier) {
        self.orb = orb
        self.onDevice = onDevice
        self.makeClassifier = makeClassifier
    }

    @ObservationIgnored private let orb: OrbControls
    @ObservationIgnored private let onDevice: OnDeviceModel
    @ObservationIgnored private let makeClassifier: () -> RequestClassifier?
    @ObservationIgnored private let router = ModelRouter()
    @ObservationIgnored private lazy var classifier: RequestClassifier? = makeClassifier()
    @ObservationIgnored private var latest = 0
    /// Whether the Sintesi parlata of the latest Richiesta is being said.
    @ObservationIgnored private var isSpeaking = false
    /// Whether the answer of the latest Richiesta is over.
    @ObservationIgnored private var isAnswered = false
    /// The latest prediction on the partial text of the Ascolto, under way or done.
    @ObservationIgnored private var prediction: Prediction?
    /// The partial text heard while a prediction was under way: predicted next, unless a newer one replaces it.
    @ObservationIgnored private var nextPrediction: ClassifierInput?
    /// Whether a prediction is under way: one at a time, so the partials do not pile up on the model.
    @ObservationIgnored private var isPredicting = false

    /// A prediction of Tipo and Variante on a partial text, by Apple Foundation Models alone.
    private struct Prediction {
        /// The partial text, as `confirms(_:)` compares it with the final one.
        let key: ClassifierInput
        /// The verdict; `nil` when the model on the Mac could not answer in time.
        let task: Task<RequestClassification?, Never>
    }

    /// Starts `richiesta` towards `provider`: Pensiero and the Tinta at once, then the classification, the router's
    /// decision and the Morph.
    ///
    /// What the Richiesta carries is measured for Apple Foundation Models while it is classified, within the same
    /// budget; a Domanda the router sends there takes the neutral Tinta.
    ///
    /// - Parameters:
    ///   - catalog: The Claude models the account offers, for the router; `nil` when not read yet.
    ///   - preferences: The user's preferences for each Tipo; an endpoint they choose gives the Orb its own Tinta.
    func submit(_ richiesta: Richiesta, to provider: Provider?, catalog: ModelCatalog? = nil,
                preferences: ModelRouter.Preferences = .none) async -> Submission {
        latest += 1
        let id = latest
        isSpeaking = false
        isAnswered = false
        orb.questionState = .thinking
        orb.provider = provider
        forecast = nil
        let predicted = takePrediction(for: richiesta.classifierInput)
        guard let classifier else {
            return Submission(id: id, classification: nil, route: router.route(for: nil, in: catalog))
        }
        let decision = Signposts.beginInterval(.intakeDecision)
        async let measured = onDevice.fit(of: richiesta.onDeviceContent)
        let classification: RequestClassification
        if let held = await predicted?.value {
            // The final text confirms the prediction: the Morph starts now, without waiting for the classifier.
            classification = held
            if id == latest { orb.variante = held.variante }
            Signposts.emit(.voicePredictionHeld)
        } else {
            classification = await classifier.classification(of: richiesta.classifierInput)
        }
        let fit = await measured
        let route = router.route(for: classification, fit: fit, hasAttachments: !richiesta.attachments.isEmpty,
                                 readsOnDevice: richiesta.isReadableOnDevice, preferences: preferences, in: catalog)
        Signposts.endInterval(.intakeDecision, decision)
        // Where the Domanda goes and what was measured: never its text.
        let fallback = route.onDeviceFallback.map { String(describing: $0) } ?? "-"
        Logger.agent.info("""
            Route \(String(describing: route.destination), privacy: .public), \
            fit \(String(describing: fit), privacy: .public), fallback \(fallback, privacy: .public)
            """)
        let tinta = switch route.destination {
        case .claude: provider
        case .onDevice: Provider?.none
        case let .endpoint(endpoint): endpoint.provider
        }
        if id == latest {
            orb.variante = classification.variante
            orb.provider = tinta
            forecast = Forecast(variante: classification.variante, provider: tinta)
        }
        return Submission(id: id, classification: classification, route: route)
    }

    /// Predicts Tipo and Variante on the partial text of the Ascolto (spec 08), only with Apple Foundation Models on the
    /// Mac; the Orb does not move until the release, when `submit` uses the prediction if the final text confirms it.
    ///
    /// Without the model on the Mac, nothing is predicted and the Morph waits for the classifier.
    func predict(_ richiesta: Richiesta) {
        let input = richiesta.classifierInput
        let key = Self.key(of: input)
        guard key != prediction?.key, key != nextPrediction.map(Self.key) else { return }
        guard !isPredicting else {
            nextPrediction = input
            return
        }
        startPrediction(of: input)
    }

    private func startPrediction(of input: ClassifierInput) {
        guard let classifier else { return }
        isPredicting = true
        let task = Task { [weak self] in
            let classification = await classifier.prediction(of: input)
            self?.endPrediction()
            return classification
        }
        prediction = Prediction(key: Self.key(of: input), task: task)
    }

    private func endPrediction() {
        isPredicting = false
        guard let next = nextPrediction else { return }
        nextPrediction = nil
        startPrediction(of: next)
    }

    /// The prediction the final `input` confirms, done or still under way, and forgets every prediction: each
    /// Ascolto starts afresh.
    private func takePrediction(for input: ClassifierInput) -> Task<RequestClassification?, Never>? {
        defer {
            prediction = nil
            nextPrediction = nil
        }
        guard let prediction, prediction.key == Self.key(of: input) else { return nil }
        return prediction.task
    }

    /// What the comparison of a partial text with the final one looks at: the words, without case or punctuation,
    /// which the final transcription adds; the Allegati as they are.
    nonisolated static func key(of input: ClassifierInput) -> ClassifierInput {
        let words = input.text.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
        return ClassifierInput(text: words.joined(separator: " "), attachmentNames: input.attachmentNames)
    }

    /// The router's decision for `richiesta` while it is typed, for the chip in the prompt: the same classification
    /// and measure as `submit`, without moving the Orb.
    ///
    /// - Parameters:
    ///   - catalog: The Claude models the account offers, for the router; `nil` when not read yet.
    ///   - preferences: The user's preferences for each Tipo.
    func forecastRoute(for richiesta: Richiesta, catalog: ModelCatalog? = nil,
                       preferences: ModelRouter.Preferences = .none) async -> Route {
        guard let classifier else { return router.route(for: nil, in: catalog) }
        async let measured = onDevice.fit(of: richiesta.onDeviceContent)
        let classification = await classifier.classification(of: richiesta.classifierInput)
        return router.route(for: classification, fit: await measured, hasAttachments: !richiesta.attachments.isEmpty,
                            readsOnDevice: richiesta.isReadableOnDevice, preferences: preferences, in: catalog)
    }

    /// Gives the Orb `provider`'s Tinta: `submission`'s answer moved to it, after Apple Foundation Models failed.
    func answer(_ submission: Submission, movedTo provider: Provider?) {
        guard submission.id == latest else { return }
        orb.provider = provider
        forecast = forecast.map { Forecast(variante: $0.variante, provider: provider) }
    }

    /// Turns the Orb to Lavora: the first token of `submission`'s answer arrived.
    func beginWorking(on submission: Submission) {
        guard submission.id == latest, !isSpeaking else { return }
        orb.questionState = .working
    }

    /// Turns the Orb to Parla: the Sintesi parlata of `submission`'s answer is being said.
    func beginSpeaking(on submission: Submission) {
        guard submission.id == latest else { return }
        isSpeaking = true
        orb.questionState = .speaking
    }

    /// Ends Parla: back to Lavora while the answer goes on, otherwise the Orb goes back to the Sessioni.
    func endSpeaking(on submission: Submission) {
        guard submission.id == latest, isSpeaking else { return }
        isSpeaking = false
        orb.voiceLevel = nil
        orb.questionState = isAnswered ? nil : .working
    }

    /// Clears what is read under the Orb, and hands the Orb back to the Sessioni unless it is still speaking:
    /// `submission` is answered, stopped or failed.
    func finish(_ submission: Submission) {
        guard submission.id == latest else { return }
        isAnswered = true
        forecast = nil
        if !isSpeaking { orb.questionState = nil }
    }

    /// The classifier of the Catalogo in the app bundle: Apple Foundation Models, then the rules.
    nonisolated static func bundledClassifier() -> RequestClassifier? {
        do {
            return RequestClassifier(catalogo: try Catalogo(bundle: .main))
        } catch {
            Logger(subsystem: "com.mgiuditta.bubo", category: "router")
                .error("Catalogo unreadable, no Morph from the classifier: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}
