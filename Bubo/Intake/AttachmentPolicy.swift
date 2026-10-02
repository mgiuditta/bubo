/// Who may receive which Allegato without asking (spec 09, Allegati e fornitori).
///
/// Claude reads every Allegato from its path or its text. A model on the Mac reads only text, so never a folder or an
/// image; whether the text fits its context is measured apart. Any other provider needs the user's consent for each
/// Allegato, which comes with #99: until then it receives none.
nonisolated enum AttachmentPolicy {
    /// Who would receive an Allegato.
    enum Recipient: Sendable {
        /// `claude`, through the agent bridge.
        case claude
        /// Apple Foundation Models, on the Mac.
        case onDevice
        /// A provider in the cloud other than Claude, such as an OpenAI-compatible endpoint.
        case otherProvider
    }

    /// Returns whether `recipient` may receive `allegato` without asking the user.
    static func allows(_ allegato: Allegato, to recipient: Recipient) -> Bool {
        switch recipient {
        case .claude: true
        case .onDevice: allegato.text != nil
        case .otherProvider: false
        }
    }
}
