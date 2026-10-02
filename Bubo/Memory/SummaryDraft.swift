import FoundationModels

/// The summary as Apple's model generates it.
@Generable
nonisolated struct SummaryDraft {
    @Guide(description: "Cosa è stato fatto nella Sessione, in frasi brevi", .maximumCount(5))
    var fatto: [String]
    @Guide(description: "Le decisioni prese", .maximumCount(5))
    var decisioni: [String]
    @Guide(description: "Cosa resta aperto o da fare", .maximumCount(5))
    var aperto: [String]
}
