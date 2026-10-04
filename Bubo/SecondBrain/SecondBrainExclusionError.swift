/// Why a folder cannot be left out of the Indice.
nonisolated enum SecondBrainExclusionError: Error, Equatable {
    /// The folder is not inside the Secondo cervello, or is the Secondo cervello itself.
    case outsideSecondBrain
}
