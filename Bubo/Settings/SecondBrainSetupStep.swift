/// One question of the guided setup of the Riunioni, in the order they are asked; the Secondo cervello itself is set up
/// in a conversation (``SecondBrainConversationSheet``), and here only its folder is asked when there is none.
enum SecondBrainSetupStep: Int, CaseIterable {
    /// Which folder: an Obsidian vault on this Mac or any folder.
    case folder
    /// Which services the calls run in: their apps come first when a Riunione starts.
    case callServices
    /// How long the audio of a Riunione stays on the Mac.
    case meetingAudio
    /// The main language of the Riunioni, in which they are transcribed.
    case meetingLanguage
}
