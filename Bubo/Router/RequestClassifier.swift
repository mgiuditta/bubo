import Foundation
import os
import Synchronization

/// The router's one entry point for classifying a request: its engines in order, each within its budget, then the rules.
///
/// Today the engines are Apple Foundation Models; Jev (#124) goes in front of them as one more `ClassificationEngine`.
/// It always answers: an engine that is unavailable, fails or runs past its budget passes the turn on, with no retry,
/// and the answer says why in `fallback`.
nonisolated struct RequestClassifier {
    /// The engines to try before the rules, first to last.
    let engines: [any ClassificationEngine]
    let rules: RuleClassifier

    private static let logger = Logger(subsystem: "com.mgiuditta.bubo", category: "router")
    private static let signposter = OSSignposter(logger: logger)

    init(engines: [any ClassificationEngine], rules: RuleClassifier) {
        self.engines = engines
        self.rules = rules
    }

    /// Creates the classifier of a Mac without Jev: Foundation Models, then the rules.
    init(catalogo: Catalogo) {
        let foundationModels = try? FoundationModelsClassifier(catalogo: catalogo)
        self.init(engines: foundationModels.map { [$0] } ?? [], rules: RuleClassifier(catalogo: catalogo))
    }

    /// Classifies `input` with the first engine that answers in time, or with the rules.
    func classification(of input: ClassifierInput) async -> RequestClassification {
        let interval = Self.signposter.beginInterval("Classification", id: Self.signposter.makeSignpostID())
        defer { Self.signposter.endInterval("Classification", interval) }
        var fallback: RequestClassification.Fallback?
        for engine in engines {
            switch await Self.outcome(of: engine, input: input) {
            case .success(let classification):
                Self.log(classification)
                return classification
            case .failure(let reason):
                fallback = reason
            }
        }
        var classification = rules.classification(of: input)
        classification.fallback = fallback
        Self.log(classification)
        return classification
    }

    /// The engine's answer, or why there is none: the first of the answer and the end of the budget wins.
    ///
    /// The deadline holds even if the engine ignores cancellation: the late answer is dropped, not awaited.
    private static func outcome(of engine: any ClassificationEngine,
                                input: ClassifierInput) async -> Result<RequestClassification, RequestClassification.Fallback> {
        await withCheckedContinuation { continuation in
            let race = Race(continuation)
            let work = Task {
                do {
                    race.finish(.success(try await engine.classification(of: input)))
                } catch let reason as RequestClassification.Fallback {
                    race.finish(.failure(reason))
                } catch {
                    race.finish(.failure(.failed))
                }
            }
            Task {
                try? await Task.sleep(for: engine.budget)
                work.cancel()
                race.finish(.failure(.timedOut))
            }
        }
    }

    private static func log(_ classification: RequestClassification) {
        // The request's text never reaches the log: only the verdict.
        logger.info("""
            Tipo \(classification.type.rawValue, privacy: .public) \
            (alt \(classification.runnerUp?.rawValue ?? "-", privacy: .public)), \
            Categoria \(classification.categoria.rawValue, privacy: .public), \
            Variante \(classification.variante?.nome ?? "-", privacy: .public), \
            \(String(describing: classification.engine), privacy: .public), \
            fallback \(classification.fallback.map { String(describing: $0) } ?? "-", privacy: .public)
            """)
    }
}

/// Resumes a continuation once, with whichever result arrives first.
nonisolated private final class Race: Sendable {
    private let continuation: Mutex<CheckedContinuation<Result<RequestClassification, RequestClassification.Fallback>, Never>?>

    init(_ continuation: CheckedContinuation<Result<RequestClassification, RequestClassification.Fallback>, Never>) {
        self.continuation = Mutex(continuation)
    }

    func finish(_ result: Result<RequestClassification, RequestClassification.Fallback>) {
        continuation.withLock { $0.take() }?.resume(returning: result)
    }
}
