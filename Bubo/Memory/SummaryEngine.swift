import Foundation

/// A model that writes the Riassunto di Sessione.
protocol SummaryEngine {
    /// Whether the model is reached over the network: without it, the next engine is tried.
    var needsNetwork: Bool { get }

    /// Summarizes the Sessione `input` describes, already filtered of its secrets.
    ///
    /// - Throws: When the model cannot answer, or its answer holds no summary.
    func summary(of input: SummaryInput) async throws -> SessionSummary

    /// Answers `prompt`, already filtered of its secrets, with a short text that follows `instructions`, for the
    /// Sessione `session`, which its cost goes to.
    ///
    /// - Throws: When the model cannot answer, or answers nothing.
    func shortText(for prompt: String, following instructions: String, session: UUID) async throws -> String
}

extension SummaryEngine {
    /// No short text: only the summary.
    func shortText(for prompt: String, following instructions: String, session: UUID) async throws -> String {
        throw SummaryEngineError.unavailable
    }
}

/// Why an engine wrote no summary.
nonisolated enum SummaryEngineError: Error, Equatable {
    /// The engine cannot run on this Mac now.
    case unavailable
    /// The model answered without any item of a summary.
    case emptyAnswer
}
