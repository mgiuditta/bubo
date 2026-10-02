import Foundation

/// An installed app that opens files: VS Code, Cursor, Zed and Xcode at the line, any other from the start
/// (spec 15).
nonisolated struct Editor: Equatable, Sendable, Identifiable {
    /// How an editor opens a file at a line.
    enum Kind: Equatable, Sendable {
        /// The `code` CLI in the bundle, `-g file:line[:column]`.
        case visualStudioCode
        /// The `cursor` CLI in the bundle, as VS Code's.
        case cursor
        /// The `cli` in the bundle, `file:line[:column]`.
        case zed
        /// `xed` in the bundle, `-l line file`.
        case xcode
        /// `open -b`, without the line.
        case other
    }

    /// The editors that open at the line, by bundle identifier, in the order the first one found is chosen.
    static let known: [(bundleID: String, kind: Kind, name: String)] = [
        ("com.microsoft.VSCode", .visualStudioCode, "Visual Studio Code"),
        ("com.todesktop.230313mzl4w4u92", .cursor, "Cursor"),
        ("dev.zed.Zed", .zed, "Zed"),
        ("com.apple.dt.Xcode", .xcode, "Xcode"),
    ]

    /// The app's bundle identifier.
    let bundleID: String
    /// Where the app is installed.
    let application: URL
    /// The name shown on the button and in the Impostazioni.
    let name: String
    let kind: Kind

    var id: String { bundleID }

    /// Creates the editor of the app `bundleID` installed at `application`, named after the app when it is not one
    /// of ``known``.
    init(bundleID: String, application: URL) {
        self.bundleID = bundleID
        self.application = application
        if let known = Self.known.first(where: { $0.bundleID == bundleID }) {
            kind = known.kind
            name = known.name
        } else {
            kind = .other
            name = application.deletingPathExtension().lastPathComponent
        }
    }

    /// The command that opens `location`, with `folder` as the window's folder when the file is inside it, so VS
    /// Code, Cursor and Zed open the worktree instead of asking whether to trust a file outside their window.
    ///
    /// - Parameter isExecutable: Whether a file can run; when the editor's CLI is missing, the file opens with
    ///   `open -b`, without the line.
    func command(opening location: SourceLocation, in folder: URL?,
                 isExecutable: (URL) -> Bool = { FileManager.default.isExecutableFile(atPath: $0.path) })
        -> (executable: URL, arguments: [String]) {
        let file = location.file.path
        let place = "\(file):\(location.line)" + (location.column.map { ":\($0)" } ?? "")
        let window: [String] = if let folder = folder?.standardizedFileURL.path, file.hasPrefix(folder + "/") {
            [folder]
        } else {
            []
        }
        let cli: URL?
        let arguments: [String]
        switch kind {
        case .visualStudioCode:
            cli = application.appending(path: "Contents/Resources/app/bin/code")
            arguments = window + ["-g", place]
        case .cursor:
            cli = application.appending(path: "Contents/Resources/app/bin/cursor")
            arguments = window + ["-g", place]
        case .zed:
            cli = application.appending(path: "Contents/MacOS/cli")
            arguments = window + [place]
        case .xcode:
            cli = application.appending(path: "Contents/Developer/usr/bin/xed")
            arguments = ["-l", String(location.line), file]
        case .other:
            cli = nil
            arguments = []
        }
        if let cli, isExecutable(cli) { return (cli, arguments) }
        return (URL(filePath: "/usr/bin/open"), ["-b", bundleID, file])
    }
}
