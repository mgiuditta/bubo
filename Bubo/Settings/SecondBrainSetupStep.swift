/// One question of the guided setup of the Secondo cervello, in the order they are asked.
enum SecondBrainSetupStep: Int, CaseIterable {
    /// Which folder: an Obsidian vault on this Mac or any folder.
    case folder
    /// Which folders at its top the Indice reads.
    case includedFolders
    /// Which folders `cerca` puts first.
    case priorityFolders

    /// The question after this one; `nil` after the last.
    var next: SecondBrainSetupStep? { SecondBrainSetupStep(rawValue: rawValue + 1) }
}
