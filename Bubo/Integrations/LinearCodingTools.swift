import Foundation

/// Bubo's custom script in Linear's `~/.linear/coding-tools.json`: Collega Linear writes it, Scollega Linear takes it
/// away (spec 16). The file is the user's: its other keys stay as they are, and one that is not valid JSON is never
/// written. The file has a single `openIssue`, so a script of the user's is kept aside and put back by Scollega.
nonisolated struct LinearCodingTools {
    /// Why the file cannot be changed.
    enum Failure: LocalizedError, Equatable {
        /// The file is not a JSON object: Bubo does not touch it.
        case notValidJSON(path: String)

        var errorDescription: String? {
            switch self {
            case let .notValidJSON(path):
                String(localized: "\(path) non è JSON valido e Bubo non lo tocca. Correggilo o spostalo, poi riprova.")
            }
        }
    }

    /// The variables Linear passes to the script.
    static let variables = ["LINEAR_PROMPT", "LINEAR_ISSUE_IDENTIFIER", "LINEAR_ISSUE_BRANCH_NAME", "LINEAR_WORK_DIR"]
    /// The defaults key of the user's `openIssue` that Collega replaced, as JSON.
    static let previousScriptKey = "linearPreviousOpenIssue"

    /// `~/.linear/coding-tools.json`.
    let file: URL
    /// The executable in Bubo's bundle that hands the issue to Bubo.
    let helper: URL
    /// Where the user's replaced `openIssue` is kept.
    let defaults: UserDefaults

    /// The file in `home`, pointing at `helper`.
    init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
         helper: URL = Bundle.main.bundleURL.appending(path: "Contents/Helpers/bubo-linear"),
         defaults: UserDefaults = .standard) {
        file = home.appending(path: ".linear/coding-tools.json")
        self.helper = helper
        self.defaults = defaults
    }

    /// Bubo's `openIssue`.
    var script: [String: Any] {
        ["path": helper.path, "args": [String](), "env": Self.variables]
    }

    /// The line Collega writes, as the confirmation shows it.
    var scriptText: String {
        Self.text(of: ["openIssue": script])
    }

    /// The `openIssue` in the file now, when it is not Bubo's: Collega replaces it, Scollega puts it back.
    ///
    /// - Throws: `Failure.notValidJSON` when the file is not a JSON object.
    func otherScriptText() throws -> String? {
        guard let current = try contents()["openIssue"], !Self.isBubo(current) else { return nil }
        return Self.text(of: ["openIssue": current])
    }

    /// Whether the file runs Bubo on Linear's issues, from this bundle or another.
    ///
    /// - Throws: `Failure.notValidJSON` when the file is not a JSON object.
    func isConnected() throws -> Bool {
        try contents()["openIssue"].map(Self.isBubo) ?? false
    }

    /// Collega Linear: writes Bubo's `openIssue`, keeping aside the user's if there is one; the rest stays.
    ///
    /// - Throws: `Failure.notValidJSON` when the file is not a JSON object, or the error of writing it.
    func connect() throws {
        var contents = try contents()
        if let current = contents["openIssue"], !Self.isBubo(current) {
            defaults.set(try JSONSerialization.data(withJSONObject: current, options: .fragmentsAllowed),
                         forKey: Self.previousScriptKey)
        }
        contents["openIssue"] = script
        try write(contents)
    }

    /// Scollega Linear: puts back the user's `openIssue` that Collega replaced, or takes Bubo's away; the rest stays.
    /// Nothing when the file does not run Bubo.
    ///
    /// - Throws: `Failure.notValidJSON` when the file is not a JSON object, or the error of writing it.
    func disconnect() throws {
        var contents = try contents()
        guard let current = contents["openIssue"], Self.isBubo(current) else { return }
        let previous = defaults.data(forKey: Self.previousScriptKey)
            .flatMap { try? JSONSerialization.jsonObject(with: $0, options: .fragmentsAllowed) }
        contents["openIssue"] = previous
        try write(contents)
        defaults.removeObject(forKey: Self.previousScriptKey)
    }

    /// The file's JSON object; empty when there is no file.
    private func contents() throws -> [String: Any] {
        let data: Data
        do {
            data = try Data(contentsOf: file)
        } catch CocoaError.fileReadNoSuchFile {
            return [:]
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.notValidJSON(path: file.path)
        }
        return object
    }

    /// Writes `contents` at once, through a symbolic link if the file is one.
    private func write(_ contents: [String: Any]) throws {
        let target = file.resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: contents,
                                              options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: target, options: .atomic)
    }

    /// Whether `script` runs a `bubo-linear` from a Bubo bundle.
    private static func isBubo(_ script: Any) -> Bool {
        ((script as? [String: Any])?["path"] as? String)?.hasSuffix(".app/Contents/Helpers/bubo-linear") ?? false
    }

    private static func text(of object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object,
                                                     options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}
