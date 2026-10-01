/// What an ingresso hands the pipeline (spec 09, step 1): today the text of the prompt scritto.
///
/// Allegati and the destination join it with the ingressi that bring them: trascinamento, Servizio, App Intent.
nonisolated struct Richiesta: Equatable, Sendable {
    /// What the user typed or said.
    let text: String

    /// What the classifier may see of the Richiesta.
    var classifierInput: ClassifierInput { ClassifierInput(text: text) }
}
