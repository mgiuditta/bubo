/// One question of the guided setup of the Secondo cervello, in the order they are asked.
enum SecondBrainSetupStep: Int, CaseIterable {
    /// Which folder: an Obsidian vault on this Mac or any folder.
    case folder
    /// Which folders at its top the Indice reads.
    case includedFolders
    /// Which folders `cerca` puts first.
    case priorityFolders
    /// Which people the user often works with: `cerca` puts first the notes naming them.
    case people
    /// Which projects the user follows: `cerca` puts first the notes naming them.
    case projects
    /// Which services the calls run in: their apps come first when a Riunione starts.
    case callServices
    /// How long the audio of a Riunione stays on the Mac.
    case meetingAudio
    /// The main language of the Riunioni, in which they are transcribed.
    case meetingLanguage

    /// The questions about the Riunioni, asked on their own at the first Riunione when the folder is already chosen.
    static let meetings: [SecondBrainSetupStep] = [.callServices, .meetingAudio, .meetingLanguage]

    /// The defaults key recording that the questions about the Riunioni were shown, so they open on their own once.
    static let meetingsShownKey = "secondBrain.setup.meetingsShown"
}
