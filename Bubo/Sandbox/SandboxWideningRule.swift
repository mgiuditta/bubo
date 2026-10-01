import Foundation

/// A Regola di permesso of Claude Code that also widens the Sandbox (spec 22): an allow `Edit(…)` or `Write(…)`
/// makes a folder writable, an allow `WebFetch(domain:…)` lets a host in. Bubo only lists it; it lives in the settings.
nonisolated struct SandboxWideningRule: Hashable, Sendable, Decodable {
    /// The rule as `claude` holds it, such as `Edit(~/altro/**)`; shown with every invisible character escaped.
    let rule: String
    /// Where `claude` read it, such as `userSettings` or `projectSettings`.
    let source: String

    /// Where the rule lives, in the user's words.
    var sourceTitle: String {
        switch source {
        case "userSettings": String(localized: "Le tue impostazioni")
        case "projectSettings": String(localized: "Impostazioni condivise del Progetto")
        case "localSettings": String(localized: "Impostazioni locali del Progetto")
        case "policySettings": String(localized: "Impostazioni dell'organizzazione")
        default: source
        }
    }
}
