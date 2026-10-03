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

    /// Installs GitHub Copilot CLI with Homebrew (ADR 0011), found in either of its folders: the `.command` shell
    /// reads no profile.
    static let installCopilot = #"PATH=/opt/homebrew/bin:/usr/local/bin:"$PATH" brew install copilot-cli"#

    /// Signs `copilot` in through the browser; the token stays where `copilot` puts it.
    static func loginCopilot(_ copilot: URL) -> String {
        "\(quoted(copilot.path)) login"
    }

    /// Diagnoses `claude` without a session: its output and exit code are not documented, so the user reads them.
    static func doctor(claude: URL) -> String {
        "\(quoted(claude.path)) doctor"
    }

    /// Updates `claude`, installed at `installation` once its links are followed.
    ///
    /// `claude update` updates only the native installation: a `claude` in a `Caskroom` is upgraded with its cask,
    /// one in npm's global `node_modules` with npm, never `npm update -g`. npm runs with its own folder first on the
    /// `PATH`, where its `node` is.
    static func update(claude: URL, installation: URL) -> String {
        let components = installation.pathComponents
        if let modules = components.firstIndex(of: "node_modules"), modules >= 2, components[modules - 1] == "lib",
           components.dropFirst(modules + 1).starts(with: ["@anthropic-ai", "claude-code"]) {
            let bin = URL(filePath: NSString.path(withComponents: Array(components[..<(modules - 1)]))).appending(path: "bin")
            return "PATH=\(quoted(bin.path)):\"$PATH\" \(quoted(bin.appending(path: "npm").path)) install -g @anthropic-ai/claude-code@latest"
        }
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
