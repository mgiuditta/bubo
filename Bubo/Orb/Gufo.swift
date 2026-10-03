import Foundation

/// The owl of the Segno, as the Orb's greeting: at the first opening of the HUD after launch the Orb turns into
/// the owl for a few seconds, then back to the Blob.
nonisolated enum Gufo {
    /// How long the greeting lasts, Morph into the owl and back included.
    static let duration: Double = 3.5
    /// How long the still owl stays with Reduce Motion on.
    static let stillDuration: Double = 2

    /// The Variante the Regia del Morph plays; it is not in the Catalogo, so no Domanda can ever choose it.
    static let variante = Variante(nome: "gufo", forma: Forma.gufo.rawValue, categoria: .creativo,
                                   descrizione: "", parole: [])

    /// How long after the greeting starts the Orb is asked back to the Blob, so the whole greeting lasts its duration.
    static func returnDelay(reducesMotion: Bool) -> Double {
        reducesMotion ? stillDuration : duration - MorphDirector.morphDuration
    }
}
