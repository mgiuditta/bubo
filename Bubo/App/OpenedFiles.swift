import Foundation

/// What Bubo does with the files the Finder hands it: a `.bubo` file from a doppio clic, a folder from «Apri con» or
/// dropped on the Dock icon.
///
/// Only the first folder counts, since the HUD shows one new Sessione at a time; any other file is ignored, as the
/// Finder hands Bubo no other kind.
nonisolated struct OpenedFiles: Equatable, Sendable {
    /// The folder the Finder hands Bubo, as a Progetto.
    enum Folder: Equatable, Sendable {
        /// A known Progetto, as Bubo keeps it: the HUD shows its latest Sessione.
        case project(URL)
        /// A folder that is no Progetto yet: the new Sessione sheet on it creates it.
        case newProject(URL)
    }

    /// The `.bubo` files, Consegne or Biglietti.
    var buboFiles: [URL] = []
    /// The first folder; `nil` for none.
    var folder: Folder?

    /// Sorts `urls` into `.bubo` files and the first folder, ignoring every other URL.
    ///
    /// - Parameters:
    ///   - projects: The known Progetti.
    ///   - isFolder: Whether a file URL is a folder.
    init(_ urls: [URL], projects: [URL], isFolder: (URL) -> Bool = OpenedFiles.isFolder) {
        for url in urls where url.isFileURL {
            if url.pathExtension.lowercased() == "bubo" {
                buboFiles.append(url)
            } else if folder == nil, isFolder(url) {
                let components = url.standardizedFileURL.pathComponents
                let known = projects.first { $0.standardizedFileURL.pathComponents == components }
                folder = known.map(Folder.project) ?? .newProject(url)
            }
        }
    }

    /// Whether `url` is a folder on disk, packages included.
    static func isFolder(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
}
