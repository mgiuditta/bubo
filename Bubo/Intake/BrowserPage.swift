import Foundation

/// The page open in the browser in front, which a Domanda asked from the Panel takes as an Allegato: Bubo knows what
/// the user is looking at.
///
/// Read with Apple Events through `osascript`, off the main thread: the first time macOS asks the user whether Bubo may
/// control that browser, and a refusal only means no page.
nonisolated enum BrowserPage {
    /// Returns the Allegato of the page in the front window of the browser `bundleID`, called `browserName`; `nil`
    /// when it is not a supported browser, has no window, shows no web page, or Bubo may not ask it.
    static func current(inBrowser bundleID: String, named browserName: String,
                        runner: ProcessRunner = .live) async -> Allegato? {
        guard let script = script(forBrowser: bundleID),
              let output = await runner.run(URL(filePath: "/usr/bin/osascript"), ["-e", script], timeout: .seconds(60)),
              output.exitCode == 0
        else { return nil }
        return allegato(fromScriptOutput: output.standardOutput, browserName: browserName)
    }

    /// Returns the AppleScript that prints the front tab's address, then its title on the next line; `nil` for a
    /// browser Bubo does not read.
    static func script(forBrowser bundleID: String) -> String? {
        let tab: String
        let title: String
        switch bundleID {
        case safari: (tab, title) = ("current tab", "name")
        case _ where chromiumBrowsers.contains(bundleID): (tab, title) = ("active tab", "title")
        default: return nil
        }
        // `application id` of a running app: it never launches one.
        return """
            tell application id "\(bundleID)"
                if (count of windows) is 0 then return ""
                set t to \(tab) of front window
                return (URL of t) & linefeed & (\(title) of t)
            end tell
            """
    }

    /// Returns the Allegato of a script's `output`, address then title; `nil` unless the address is a web page.
    static func allegato(fromScriptOutput output: String, browserName: String) -> Allegato? {
        let lines = output.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        guard let first = lines.first,
              let address = URL(string: first.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(address.scheme?.lowercased()), let host = address.host()
        else { return nil }
        let title = lines.count > 1 ? lines[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
        let shown = title.isEmpty ? host : title
        let name = shown.count > nameLength ? shown.prefix(nameLength) + "…" : shown
        // The words tell the model this is what the user has in front, not something they dragged.
        let text = title.isEmpty ? "Pagina aperta in \(browserName): \(address.absoluteString)"
            : "Pagina aperta in \(browserName): \(title)\n\(address.absoluteString)"
        return Allegato(name: name, text: text)
    }

    private static let safari = "com.apple.Safari"
    /// The Chromium browsers, which share Chrome's scripting dictionary; Arc among them.
    private static let chromiumBrowsers: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.brave.Browser", "com.microsoft.edgemac",
        "company.thebrowser.Browser", "com.vivaldi.Vivaldi",
    ]
    /// The characters of a title that name the chip, as for a dragged text.
    private static let nameLength = 32
}
