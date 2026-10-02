import CoreServices
import Foundation

/// Tells when `claude` may have appeared or signed in, from FSEvents and never by polling (spec 26).
///
/// It watches the folders the installers put `claude` in, and the home folder for `~/.claude.json`, which `claude`
/// replaces at each login: a watch on the file alone would be lost at the first rewrite. Only events, never contents.
/// The paths are compared as FSEvents reports them, without symbolic links: the home folder must have none.
nonisolated struct InstallWatcher: Sendable {
    /// Where `claude` is looked for.
    var locator = ClaudeLocator()
    /// Whether a folder exists; the only file system access besides FSEvents.
    var folderExists: @Sendable (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    /// How long FSEvents gathers events before delivering them.
    var latency: TimeInterval = 0.5

    /// The files whose creation or change matters: every place `claude` is installed, and `~/.claude.json`.
    var watchedFiles: Set<String> {
        Set((locator.candidates + [locator.home.appending(path: ".claude.json")]).map(\.path))
    }

    /// The folders FSEvents watches: under the home folder the closest one that exists, elsewhere only folders that
    /// exist, so a missing `/opt/homebrew` never turns into a watch on `/`.
    var roots: [String] {
        let home = locator.home
        let folders = (locator.candidates + [locator.home.appending(path: ".claude.json")]).compactMap { file -> URL? in
            var folder = file.deletingLastPathComponent()
            guard folder.path == home.path || folder.path.hasPrefix(home.path + "/") else { return folderExists(folder) ? folder : nil }
            while !folderExists(folder) && folder.path != home.path { folder.deleteLastPathComponent() }
            return folder
        }
        let paths = Set(folders.map(\.path))
        return paths.filter { path in !paths.contains { path != $0 && path.hasPrefix($0 + "/") } }.sorted()
    }

    /// One element each time a watched file may have changed, until the iteration ends.
    ///
    /// `~/Library` is left out: it changes all the time and holds none of the watched files.
    func changes() -> AsyncStream<Void> {
        let files = watchedFiles
        let library = locator.home.appending(path: "Library").path
        let batches = FileEvents.batches(under: roots, excluding: [library],
                                         since: FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency: latency)
        return AsyncStream { continuation in
            let watch = Task {
                for await batch in batches where Self.matters(batch, files: files) { continuation.yield() }
                continuation.finish()
            }
            continuation.onTermination = { _ in watch.cancel() }
        }
    }

    /// Whether `batch` touches one of `files`, or lost events and may have.
    static func matters(_ batch: FileEventBatch, files: Set<String>) -> Bool {
        batch.needsRescan || batch.paths.contains(where: files.contains)
    }
}
