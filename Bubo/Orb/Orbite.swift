import Foundation

/// The Orbite: a hidden Morph that turns the Orb into an orbital diagram for a few seconds, then back to the Blob.
///
/// Nothing in the interface points to it: the prompt made of its word alone plays it instead of becoming a Domanda.
nonisolated enum Orbite {
    /// The word that plays the Orbite.
    static let word = "twelfth"
    /// How long the Orbite lasts, Morph into the diagram and back included.
    static let duration: Double = 6
    /// How long the still diagram stays with Reduce Motion on.
    static let stillDuration: Double = 3

    /// The Variante the Regia del Morph plays; it is not in the Catalogo, so no Domanda can ever choose it.
    static let variante = Variante(nome: "orbite", forma: Forma.orbite.rawValue, categoria: .creativo,
                                   descrizione: "", parole: [])

    /// Whether `prompt` plays the Orbite: only the word alone, ignoring case and the spaces around it.
    static func isPlayed(by prompt: String) -> Bool {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines).compare(word, options: .caseInsensitive) == .orderedSame
    }

    /// How long after the Orbite starts the Orb is asked back to the Blob, so the whole show lasts its duration.
    static func returnDelay(reducesMotion: Bool) -> Double {
        reducesMotion ? stillDuration : duration - MorphDirector.morphDuration
    }

    /// The diagram's clock at `time`, for an Orbite started at `start`; with Reduce Motion it stays still at zero.
    static func diagramTime(since start: Double, at time: Double, reducesMotion: Bool) -> Float {
        reducesMotion ? 0 : Float(max(0, time - start))
    }
}
