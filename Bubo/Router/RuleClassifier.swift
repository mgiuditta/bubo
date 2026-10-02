import Foundation

/// Classifies a request with weighted keywords in Italian and English: the fallback that always answers, offline and in microseconds.
///
/// Each Tipo collects points from the words that point to it; signs of a codebase (identifiers, source files, words such as
/// "repo" or "branch") make the Sessione Tipi count in full, and without them a Sessione Tipo counts half. Two Tipi with the same
/// points are a hesitation, and the router takes the stronger default of the two.
nonisolated struct RuleClassifier: ClassificationEngine {
    let catalogo: Catalogo

    /// The rules never time out; the budget only matters to engines that can be slow.
    var budget: Duration { .seconds(1) }

    func classification(of input: ClassifierInput) -> RequestClassification {
        let text = Self.normalized(input.text)
        let codeEvidence = Self.codeEvidence(in: input, normalized: text)
        let hasAttachments = !input.attachmentNames.isEmpty

        var scores: [RequestType: Double] = [:]
        for (type, keywords) in Self.keywords {
            let points = keywords.reduce(0.0) { $0 + (Self.contains($1.word, in: text) ? $1.weight : 0) }
            scores[type] = type.isSession ? (codeEvidence > 0 ? points + Double(codeEvidence) : points / 2) : points
        }
        // A Sessione with nothing more specific to say is a small fix; a Domanda, a short fact.
        scores[.smallFix, default: 0] += codeEvidence > 0 ? 0.5 : 0
        scores[.shortFact, default: 0] += 1
        if hasAttachments {
            scores[.summary, default: 0] += 1
        }
        // A long question with no other sign asks to think it through.
        if text.split(separator: " ").count >= 22, input.text.contains("?") {
            scores[.reasoning, default: 0] += 1.5
        }

        // Ties go to the stronger default, then to the order of the list, so the same text always gets the same Tipo.
        let ranked = RequestType.allCases.map { ($0, scores[$0, default: 0]) }.sorted {
            $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.defaultStrength > $1.0.defaultStrength
        }
        let first = (key: ranked[0].0, value: ranked[0].1), second = (key: ranked[1].0, value: ranked[1].1)
        let categoria = categoria(of: text, type: first.key)
        return RequestClassification(candidate: first.key, alternative: second.value == first.value ? second.key : nil,
                                     categoria: categoria.categoria,
                                     variante: variante(in: categoria.categoria, text: text, isClear: categoria.isClear),
                                     engine: .rules)
    }

    // MARK: Categoria and Variante

    /// The Categoria with the most keyword points, whether any word pointed to it, and whether it won clearly.
    ///
    /// A Sessione is Codice, Agente or Ricerca, and Codice without a sign; a Domanda without a sign is Chat, the generic
    /// Categoria. Exploring the code to find
    /// something is Ricerca, as the labelled set and the Variante `lente` say.
    private func categoria(of text: String, type: RequestType) -> (categoria: Categoria, isEvident: Bool, isClear: Bool) {
        var points: [Categoria: Double] = [:]
        // A Sessione works on a Progetto: its code, its agents, or a search through it.
        let candidates: [Categoria] = type.isSession ? [.codice, .agente, .ricerca] : Categoria.allCases
        for categoria in candidates {
            let words = (Self.categoriaKeywords[categoria] ?? []) + catalogo.varianti(in: categoria).flatMap(\.parole)
            points[categoria] = Set(words).reduce(0.0) { $0 + (Self.contains($1, in: text) ? 1 : 0) }
        }
        if type == .explore, Self.searchWords.contains(where: { Self.contains($0, in: text) }) {
            points[.ricerca, default: 0] += 2
        }
        // Ties go to the order of the list, so the same text always gets the same Categoria.
        let ranked = candidates.map { ($0, points[$0, default: 0]) }.sorted { $0.1 > $1.1 }
        guard ranked[0].1 > 0 else { return (type.isSession ? .codice : .chat, type.isSession, false) }
        return (ranked[0].0, true, ranked[0].1 - ranked[1].1 >= 1)
    }

    /// The Variante of `categoria` whose words appear most in `text`; with none, its first Variante when the Categoria won
    /// clearly; otherwise `nil` for Blob with the Categoria, since a wrong Morph is worse than none.
    private func variante(in categoria: Categoria, text: String, isClear: Bool) -> Variante? {
        guard isClear else { return nil }
        let candidates = catalogo.varianti(in: categoria)
        let scored = candidates.map { variante in
            (variante, variante.parole.count { Self.contains($0, in: text) })
        }
        if let best = scored.max(by: { $0.1 < $1.1 }), best.1 > 0 {
            return best.0
        }
        return candidates.first
    }

    /// Words that ask to find something, which turn exploring the code into Ricerca.
    private static let searchWords = ["trova", "cerca", "find", "search", "look up"]

    // MARK: Text

    /// `text` lowercased, without accents and Italian elided articles ("all'apertura" is "apertura"), with every run of
    /// non-alphanumerics turned into one space and a space at both ends.
    static func normalized(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacing(/\b(l|un|c|d|dell|nell|all|dall|sull|quell|quest)['’]/, with: "")
        let words = folded.split { !$0.isLetter && !$0.isNumber }
        return " " + words.joined(separator: " ") + " "
    }

    /// Whether the normalized `text` contains `keyword`: a whole word or phrase, or with a trailing `*` any word that starts so.
    static func contains(_ keyword: String, in text: String) -> Bool {
        keyword.hasSuffix("*") ? text.contains(" " + keyword.dropLast()) : text.contains(" " + keyword + " ")
    }

    /// How strongly the request is about a codebase, from 0 to 2: code words, identifiers and source files.
    private static func codeEvidence(in input: ClassifierInput, normalized text: String) -> Int {
        var points = codeWords.count { contains($0, in: text) }
        let identifiers = input.text.split { $0.isWhitespace || ",;:()\"'?".contains($0) }.filter { token in
            token.contains(/^[a-z]+[A-Z][A-Za-z]*$|^[A-Z][a-z]+[A-Z][A-Za-z]*$|^\w+\.(swift|ts|js|py|json|yml|sh)$|^\/\w+|_\w/)
        }
        points += identifiers.count
        points += input.attachmentNames.count { name in
            sourceExtensions.contains(URL(filePath: name).pathExtension.lowercased())
        }
        return min(points, 2)
    }

    private static let sourceExtensions: Set<String> = ["swift", "ts", "js", "py", "rb", "go", "rs", "java", "kt", "c", "m", "h", "cpp"]

    // MARK: Keywords

    private struct Keyword {
        let word: String
        let weight: Double
    }

    private static func words(_ weight: Double, _ words: String...) -> [Keyword] {
        words.map { Keyword(word: $0, weight: weight) }
    }

    /// Words of a codebase, in both languages.
    private static let codeWords = [
        "codice", "code", "repo", "progetto", "project", "modul*", "pacchett*", "package", "test", "tests", "testing",
        "build", "pr", "pull request", "branch", "ramo", "diff", "commit*", "api", "endpoint*", "funzion*", "function*",
        "database", "refactor*", "app", "cli", "mcp", "hook*", "skill*", "backend", "client*", "parser", "linter", "query",
        "queries", "sql", "readme", "swift", "xcode", "ci", "workflow", "bottone", "button", "login", "crash*", "timeout",
        "monolite", "monolith", "dipendenz*", "dependenc*", "plugin*", "variabil*", "variable", "schermat*", "screen*",
        "editor", "localizz*", "locali*", "persistence", "codable", "cache", "store", "servizio", "services", "viste",
        "views", "server", "subagent", "agents", "script", "scripts", "todo", "control", "framework", "migrazion*",
        "merge", "cartella", "folder", "csv", "export", "picker",
    ]

    /// Words that point to each Tipo, with their weight.
    private static let keywords: [RequestType: [Keyword]] = [
        .plan: words(3, "piano", "pianifica*", "plan", "outline", "strategia", "strategy", "scaletta", "passi", "steps",
                     "fasi", "phases", "roadmap", "rollout", "progetta", "prima di toccare", "before touching",
                     "before implementing", "prima di tutto", "no edits", "niente modifiche", "non implementar*",
                     "propose a design", "how should we", "lay out", "sketch", "affronteresti", "organizza*", "ordine dei lavori"),
        .review: words(3, "rivedi*", "revisione", "review*", "audit*", "critique", "critica", "occhiata",
                       "second pair of eyes", "go over", "safe to merge", "cosa non va", "sono corrette", "regressions")
            + words(2, "controlla", "check"),
        .explore: words(2, "dove", "where", "chi chiama", "who calls", "come funziona", "how does", "how are", "spiega*",
                        "explain", "descriv*", "describe", "trova", "find", "cerca", "elenco", "list", "which", "quali",
                        "show me", "trace", "cosa fa", "what does", "non cambiare", "don t modify", "differenza",
                        "point me", "voglio capire", "cosa vedi", "perche", "what happens"),
        .broadChange: words(2, "tutto", "tutta", "tutti", "tutte", "ogni", "all", "every", "everywhere", "whole", "across",
                            "da zero", "from scratch", "including tests", "e test", "e aggiorna", "and update", "full")
            + words(1.5, "implementa", "implement", "migra", "migrate", "move", "porta", "convert", "replace",
                    "sostituisci", "introduce", "create", "crea", "multi"),
        .smallFix: words(1.5, "sistema*", "correggi", "fix", "rinomina", "rename", "change", "cambia", "alza", "abbassa",
                         "togli*", "remove", "rimuovi", "guard", "swap", "make", "metti", "update it", "escape", "refuso",
                         "typo", "off by one", "fallisce", "failing", "crasha", "leaks", "duplicate", "deve essere",
                         "instead of", "invece di", "al contrario"),
        .summary: words(3, "riassum*", "riassunto", "sintesi", "summar*", "gist", "tl dr", "takeaway", "punti chiave",
                        "key points", "sum up", "di cosa parla", "accorcia", "in breve"),
        .writing: words(3, "scrivi*", "write", "draft", "prepara", "rispondi", "riscrivi", "rewrite", "inventa",
                        "turn these notes", "grammatica", "titoli", "titles")
            + words(1, "poesia", "poem", "lyrics", "limerick", "storia", "bio", "caption", "messaggio", "message",
                    "mail", "email", "reminder", "announcement", "descrizione"),
        .reasoning: words(3, "conviene", "pro e contro", "pro e i contro", "pros and cons", "ragiona*", "reason*", "dimostra", "prove",
                          "decid*", "walk through", "trap", "worth it", "fairest", "and why", "complessita", "complexity",
                          "passaggi", "motiva", "both sides", "smarter", "conceptually", "compare")
            + words(2, "meglio", "should", "perche", "why", "pesa", "confronta")
            + words(1, "o", "or"),
        .webSearch: words(2, "cerca", "trova", "search", "find", "look up", "notizie", "news", "ultime", "latest",
                          "recent*", "aggiornat*", "current", "right now", "oggi", "stasera", "ieri", "domattina",
                          "this weekend", "last night", "near me", "vicino", "prezzo", "price", "orari", "borsa",
                          "prossimo anno", "next year", "this year", "quest anno", "online", "ufficiale", "official"),
        .shortFact: words(1, "cos e", "what does", "qual e", "quanti", "quante", "how many", "chi ha scritto",
                          "come si dice", "what s the", "che ore", "what day", "do i need"),
    ]

    /// Words that point to each Categoria beyond the words of its Varianti.
    private static let categoriaKeywords: [Categoria: [String]] = [
        .codice: ["codice", "code", "repo", "modul*", "test", "build", "pr", "branch", "diff", "api", "funzion*", "function",
                  "database", "refactor*", "app", "cli", "parser", "query", "readme", "swift", "xcode", "algoritm*",
                  "algorithm", "log", "changelog", "recursive", "ricorsiv*", "endpoint*", "bottone", "button"],
        .meteo: ["weather", "uv", "storm", "temporale", "forecast", "temperature", "percepita"],
        .musica: ["music", "song", "album", "guitar", "chitarra", "viola", "jazz", "concert*", "setlist",
                  "suonano", "coldplay", "radiohead", "bohemian", "rhapsody"],
        .tempo: ["ore", "time", "day", "giorni", "seconds", "week", "settimana", "natale", "daylight", "meeting", "orario", "agenda"],
        .mail: ["newsletter", "thread", "bcc", "out of office", "recruiter", "follow up"],
        .ricerca: ["notizie", "news", "recensioni", "reviews", "documentazione", "articles", "benchmarks", "release notes",
                   "find", "where", "partita", "ristorante", "prezzo"],
        .creativo: ["poesia", "poem", "haiku", "storia", "story", "lyrics", "limerick", "logo", "fonts", "titoli",
                    "descrizione di un prodotto", "buonanotte"],
        .finanza: ["mutuo", "loan", "spread", "btp", "apr", "invoice", "fattura", "bilancio", "euro", "dollar", "borsa",
                   "titolo", "risparmio", "invest", "risparmi*", "pay", "dispute"],
        .salute: ["calorie", "heart", "referto", "vaccino", "pharmacies", "farmaci*", "corsa", "pesi", "fasting", "study"],
        .viaggi: ["tren*", "train", "rail", "aereo", "itinerary", "entry requirements", "plug adapter", "packing", "hiking",
                  "parigi", "roma"],
        .chat: ["slack", "chat"],
        .agente: ["agent", "agents", "subagent", "mcp", "hook*", "skill*", "automazione", "automation", "claude"],
    ]
}
