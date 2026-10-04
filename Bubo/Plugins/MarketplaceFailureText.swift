import SwiftUI

extension Text {
    /// What a Marketplace command that did not reach its goal says: one line of explanation when git had no
    /// credentials, otherwise the CLI's own words.
    init(marketplaceFailure result: PluginCommandResult) {
        if result.isAccessDenied {
            self.init("Accesso al repository negato: configura una chiave SSH o un credential helper di git.")
        } else if result.failureCode == "not_listed" {
            self.init("claude ha finito senza errori, ma l'elenco dei marketplace non è cambiato.")
        } else if result.message.isEmpty {
            self.init("claude si è fermato senza dire com'è andata.")
        } else {
            self.init(verbatim: result.message)
        }
    }

    /// What a Marketplace command that gave no result says.
    init(marketplaceError error: any Error) {
        if let error = error as? PluginCLIError {
            self.init(error.message)
        } else {
            self.init(verbatim: error.localizedDescription)
        }
    }
}
