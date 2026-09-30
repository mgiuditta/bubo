/// The thematic group of a Variante; the raw value is how `catalogo.json` spells it.
nonisolated enum Categoria: String, CaseIterable, Decodable, Sendable {
    case codice, meteo, musica, tempo, mail, ricerca, creativo, finanza, salute, viaggi, chat, agente
}
