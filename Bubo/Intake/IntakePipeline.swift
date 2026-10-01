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
    /// - Parameter makeClassifier: Builds the classifier on the first Richiesta, so launch does not pay for it; `nil` when
    ///   it cannot be built, and then the Orb keeps its Forma.
    init(orb: OrbControls = .shared, makeClassifier: @escaping () -> RequestClassifier? = IntakePipeline.bundledClassifier) {
        self.orb = orb
        self.makeClassifier = makeClassifier
    }

    @ObservationIgnored private let orb: OrbControls
    @ObservationIgnored private let makeClassifier: () -> RequestClassifier?
    @ObservationIgnored private let router = ModelRouter()
    @ObservationIgnored private lazy var classifier: RequestClassifier? = makeClassifier()
    @ObservationIgnored private var latest = 0

    /// Starts `richiesta` towards `provider`: Pensiero and the Tinta at once, then the classification, the router's
    /// decision and the Morph.
    ///
    /// - Parameter catalog: The Claude models the account offers, for the router; `nil` when not read yet.
    func submit(_ richiesta: Richiesta, to provider: Provider?, catalog: ModelCatalog? = nil) async -> Submission {
        latest += 1
        let id = latest
        orb.questionState = .thinking
        orb.provider = provider
        forecast = nil
        guard let classifier else {
            return Submission(id: id, classification: nil, route: router.route(for: nil, in: catalog))
        }
        let decision = Signposts.beginInterval(.intakeDecision)
        let classification = await classifier.classification(of: richiesta.classifierInput)
        let route = router.route(for: classification, in: catalog)
        Signposts.endInterval(.intakeDecision, decision)
        if id == latest {
            orb.variante = classification.variante
            forecast = Forecast(variante: classification.variante, provider: provider)
        }
        return Submission(id: id, classification: classification, route: route)
    }

    /// Turns the Orb to Lavora: the first token of `submission`'s answer arrived.
    func beginWorking(on submission: Submission) {
        guard submission.id == latest else { return }
        orb.questionState = .working
    }

    /// Hands the Orb back to the Sessioni, and clears what is read under it: `submission` is answered, stopped or failed.
    func finish(_ submission: Submission) {
        guard submission.id == latest else { return }
        orb.questionState = nil
        forecast = nil
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
