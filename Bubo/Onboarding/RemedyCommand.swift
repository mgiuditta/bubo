import Foundation

/// The commands the remedies of the onboarding type in the Terminal, for the user to run (spec 26).
///
/// They name `claude` by its full path: the `.command` shell reads no profile, and the login must reach the same
/// `claude` that will answer.
nonisolated enum RemedyCommand {
    /// The native installer of Claude Code.
    static let install = "curl -fsSL https://claude.ai/install.sh | bash"

    /// Signs `claude` in through the browser.
    static func login(claude: URL) -> String {
        "\(quoted(claude.path)) auth login"
    }

    /// Diagnoses `claude` without a session: its output and exit code are not documented, so the user reads them.
    static func doctor(claude: URL) -> String {
        "\(quoted(claude.path)) doctor"
    }

    /// Updates `claude`, installed at `installation` once its links are followed.
    ///
    /// `claude update` does not update a Homebrew cask, so a `claude` in a `Caskroom` is upgraded with that cask.
    // ponytail: until spec 27 (#225) chooses the command with ClaudeCompatibility.
    static func update(claude: URL, installation: URL) -> String {
        let components = installation.pathComponents
        if let caskroom = components.firstIndex(of: "Caskroom"), caskroom + 1 < components.count {
            let brew = URL(filePath: NSString.path(withComponents: Array(components[..<caskroom]))).appending(path: "bin/brew")
            return "\(quoted(brew.path)) upgrade \(quoted(components[caskroom + 1]))"
        }
        return "\(quoted(claude.path)) update"
    }

    /// `text` as the shell reads it: as it is when it has only safe characters, in single quotes otherwise.
    private static func quoted(_ text: String) -> String {
        let safe = text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "/._-@+".contains($0)) }
        return safe ? text : "'" + text.replacing("'", with: #"'\''"#) + "'"
    }
}
