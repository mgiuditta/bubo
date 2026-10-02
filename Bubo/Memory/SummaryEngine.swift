import Foundation

/// A model that writes the Riassunto di Sessione.
protocol SummaryEngine {
    /// Whether the model is reached over the network: without it, the next engine is tried.
    var needsNetwork: Bool { get }

    /// Summarizes the Sessione `input` describes, already filtered of its secrets.
    ///
    /// - Throws: When the model cannot answer, or its answer holds no summary.
    func summary(of input: SummaryInput) async throws -> SessionSummary
}

/// Why an engine wrote no summary.
nonisolated enum SummaryEngineError: Error, Equatable {
    /// The engine cannot run on this Mac now.
    case unavailable
    /// The model answered without any item of a summary.
    case emptyAnswer
}
