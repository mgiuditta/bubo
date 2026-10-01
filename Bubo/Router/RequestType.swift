/// The Tipo di richiesta: the closed list the router sorts every request into, five per family.
///
/// The raw value is how the labelled set of `BuboTests/Fixtures/richieste-etichettate.json` spells it.
nonisolated enum RequestType: String, CaseIterable, Codable, Sendable {
    case plan = "sessione.pianifica"
    case smallFix = "sessione.correzione-piccola"
    case broadChange = "sessione.modifica-ampia"
    case explore = "sessione.esplora"
    case review = "sessione.revisione"
    case shortFact = "domanda.fatto-breve"
    case summary = "domanda.riassunto"
    case writing = "domanda.scrittura"
    case reasoning = "domanda.ragionamento"
    case webSearch = "domanda.ricerca-web"

    /// Whether the request is work on a Progetto (a Sessione) rather than a Domanda.
    var isSession: Bool {
        rawValue.hasPrefix("sessione.")
    }

    /// How strong this Tipo's default model · sforzo is, from the defaults of spec 10; higher is stronger.
    ///
    /// When a classifier hesitates between two Tipi the router takes the stronger default of the two.
    var defaultStrength: Int {
        switch self {
        case .plan, .review: 5  // Opus · alto
        case .broadChange, .reasoning: 4  // Opus · medio
        case .smallFix, .writing: 3  // Sonnet · medio
        case .explore, .webSearch: 2  // Sonnet · basso
        case .summary: 1  // Haiku
        case .shortFact: 0  // Apple FM, otherwise Haiku
        }
    }
}
