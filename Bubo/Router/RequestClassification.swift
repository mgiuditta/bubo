/// What a classifier sees of a request: its text and the names of its Allegati, never their contents.
///
/// It is also all a remote classifier such as Jev may ever receive (spec 10): no file, diff or memory of the Progetto.
nonisolated struct ClassifierInput: Hashable, Sendable {
    /// What the user asked, typed or spoken.
    let text: String
    /// The file names of the Allegati, without their paths.
    let attachmentNames: [String]

    init(text: String, attachmentNames: [String] = []) {
        self.text = text
        self.attachmentNames = attachmentNames
    }
}

/// A classifier's verdict on one request: the Tipo di richiesta, and the Categoria and Variante for the Orb.
nonisolated struct RequestClassification: Equatable, Sendable {
    /// The engine that produced a classification.
    enum Engine: Equatable, Sendable {
        case foundationModels, rules
    }

    /// Why a classification fell back to the rules instead of coming from the engine before them.
    enum Fallback: Error, Equatable, Sendable {
        /// The on-device model cannot run: Apple Intelligence off, Mac not eligible, model not ready, language unsupported.
        case unavailable
        /// The engine did not answer within its latency budget.
        case timedOut
        /// The engine answered with an error or with something outside the closed lists.
        case failed
    }

    /// The Tipo the router uses: with two candidates, the one with the stronger default.
    let type: RequestType
    /// The weaker Tipo the classifier hesitated over, so the reason line can name both; `nil` when it was sure.
    let runnerUp: RequestType?
    /// The thematic group, which the Orb shows even when no Variante fits.
    let categoria: Categoria
    /// The Variante for the Orb; `nil` means Blob with the Categoria.
    let variante: Variante?
    let engine: Engine
    /// Why an earlier engine was skipped; `nil` when the first engine answered.
    var fallback: Fallback?

    init(type: RequestType, runnerUp: RequestType? = nil, categoria: Categoria, variante: Variante?,
         engine: Engine, fallback: Fallback? = nil) {
        self.type = type
        self.runnerUp = runnerUp
        self.categoria = categoria
        self.variante = variante
        self.engine = engine
        self.fallback = fallback
    }

    /// Creates a classification from two candidate Tipi, keeping the stronger default and naming the other.
    ///
    /// - Parameter alternative: The second Tipo the engine considered, or `nil` (or the same Tipo) when it was sure.
    init(candidate: RequestType, alternative: RequestType?, categoria: Categoria, variante: Variante?, engine: Engine) {
        if let alternative, alternative != candidate {
            let stronger = alternative.defaultStrength > candidate.defaultStrength ? alternative : candidate
            self.init(type: stronger, runnerUp: stronger == candidate ? alternative : candidate,
                      categoria: categoria, variante: variante, engine: engine)
        } else {
            self.init(type: candidate, categoria: categoria, variante: variante, engine: engine)
        }
    }
}

/// One way of classifying a request; the router tries its engines in order and ends with the rules.
///
/// A remote engine such as Jev conforms by sending only `ClassifierInput` and answering within its `budget`.
nonisolated protocol ClassificationEngine: Sendable {
    /// How long the router waits for this engine before falling back to the next one.
    var budget: Duration { get }
    /// Whether the engine runs on the Mac, sending nothing over the network: only such an engine predicts on the
    /// partial text of the Ascolto (spec 08).
    var runsOnDevice: Bool { get }

    /// Classifies `input`.
    ///
    /// - Throws: `RequestClassification.Fallback` when the engine cannot or will not answer.
    func classification(of input: ClassifierInput) async throws -> RequestClassification
}

nonisolated extension ClassificationEngine {
    /// An engine runs elsewhere unless it says otherwise.
    var runsOnDevice: Bool { false }
}
