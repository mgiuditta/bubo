/// The trust label of an entry: "solo testo", "esegue codice", "componenti sconosciuti".
nonisolated enum PluginTrust: Sendable, Equatable {
    case textOnly, runsCode, unknown
}
