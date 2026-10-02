/// What an ingresso hands the pipeline (spec 09, step 1): the text of the prompt and its Allegati.
///
/// The destination joins it with the ingressi that bring it: Servizio, App Intent.
nonisolated struct Richiesta: Equatable, Sendable {
    /// What the user typed or said.
    let text: String
    /// What comes with the text; empty for a prompt scritto alone.
    let attachments: [Allegato]

    init(text: String, attachments: [Allegato] = []) {
        self.text = text
        self.attachments = attachments
    }

    /// What the classifier may see of the Richiesta: the text and the Allegati's names, never their content.
    var classifierInput: ClassifierInput {
        ClassifierInput(text: text, attachmentNames: attachments.map(\.name))
    }

    /// What must fit in the on-device model's share of the context: the Allegati, or the text when there are none.
    var onDeviceContent: String {
        attachments.isEmpty ? text : attachments.map(\.text).joined(separator: "\n\n")
    }
}
