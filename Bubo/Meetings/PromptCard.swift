import Foundation

/// One answer of the Suggeritore: the question heard, and what Bubo found in the notes.
struct PromptCard: Identifiable, Equatable {
    let id = UUID()
    /// The question, as heard or written.
    var question: String
    var reason: PromptTrigger.Reason
    /// The answer so far, with its notes cited as `[[nota#punto]]`.
    var answer = ""
    /// Whether the answer is still arriving.
    var isAnswering = true
    /// Why there is no answer, when Claude could not give one.
    var failure: String?
}
