import Foundation

/// Where a Marketplace entry's plugin comes from, as `marketplace.json` declares it.
nonisolated enum PluginSource: Sendable, Equatable {
    /// A folder inside the Marketplace's repository, such as `./plugins/name`.
    case relative(path: String)
    case github(repo: String)
    case url(String)
    case gitSubdirectory(url: String, path: String)
    case npm(package: String)
    case archive(String)
    /// A command run on the Mac that prints the plugin's folder.
    case command(String)
    case unknown

    /// Reads the `source` of a Marketplace entry: a string for a relative path, an object otherwise.
    init(json: Any?) {
        if let path = json as? String {
            self = .relative(path: path)
            return
        }
        guard let object = json as? [String: Any] else {
            self = .unknown
            return
        }
        let url = object["url"] as? String
        switch object["source"] as? String {
        case "github": self = (object["repo"] as? String).map { .github(repo: $0) } ?? .unknown
        case "url", "git": self = url.map { .url($0) } ?? .unknown
        case "git-subdir": self = url.map { .gitSubdirectory(url: $0, path: object["path"] as? String ?? "") } ?? .unknown
        case "npm": self = (object["package"] as? String).map { .npm(package: $0) } ?? .unknown
        case "archive": self = url.map { .archive($0) } ?? .unknown
        case "command": self = (object["command"] as? String).map { .command($0) } ?? .unknown
        default: self = .unknown
        }
    }
}
