import Foundation

/// Why a `claude auth` command did not succeed.
enum ClaudeCLIError: LocalizedError, Equatable {
    /// No `claude` executable on the user's login `PATH`.
    case cliMissing
    /// `claude` exited with a nonzero status.
    case failed(exitCode: Int32)

    var errorDescription: String? {
        switch self {
        case .cliMissing:
            String(localized: "Non trovo la CLI claude.")
        case .failed(let exitCode):
            String(localized: "claude si è fermato con il codice \(exitCode).")
        }
    }
}
