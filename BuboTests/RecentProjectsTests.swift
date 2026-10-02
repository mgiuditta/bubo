import Foundation
import Synchronization
import Testing
@testable import Bubo

struct RecentProjectsTests {
    /// A disk with `.claude.json`, some folders and files, and the dates of the folders in `~/.claude/projects`; it
    /// records every path it is asked about.
    final class FakeDisk: Sendable {
        let touched = Mutex<[String]>([])
        let configuration: String
        let folders: Set<String>
        let files: Set<String>
        let dates: [String: Date]

        init(configuration: String, folders: Set<String> = [], files: Set<String> = [], dates: [String: Date] = [:]) {
            self.configuration = configuration
            self.folders = folders
            self.files = files
            self.dates = dates
        }

        var fileSystem: RecentProjects.FileSystem {
            RecentProjects.FileSystem(
                contents: { [self] url in
                    touched.withLock { $0.append(url.path) }
                    return url.path == "/Users/ada/.claude.json" ? Data(configuration.utf8) : nil
                },
                isFolder: { [self] url in
                    touched.withLock { $0.append(url.path) }
                    return folders.contains(url.path) ? true : files.contains(url.path) ? false : nil
                },
                modificationDate: { [self] url in
                    touched.withLock { $0.append(url.path) }
                    return dates[url.lastPathComponent]
                })
        }

        func load() -> [RecentProject] {
            RecentProjects.load(home: URL(filePath: "/Users/ada", directoryHint: .isDirectory), fileSystem: fileSystem)
        }
    }

    static func configuration(_ paths: [String]) -> String {
        let projects = paths.map { #""\#($0)": {"hasTrustDialogAccepted": true, "lastCost": 1.2}"# }
            .joined(separator: ", ")
        return #"{"oauthAccount": {"emailAddress": "ada@example.com"}, "projects": {\#(projects)}}"#
    }

    @Test func ordersByTheLastConversationAndKeepsThree() {
        let paths = ["/Users/ada/a", "/Users/ada/b", "/Users/ada/c", "/Users/ada/d"]
        let disk = FakeDisk(configuration: Self.configuration(paths), folders: Set(paths),
                            dates: ["-Users-ada-a": .init(timeIntervalSince1970: 1),
                                    "-Users-ada-b": .init(timeIntervalSince1970: 4),
                                    "-Users-ada-c": .init(timeIntervalSince1970: 3),
                                    "-Users-ada-d": .init(timeIntervalSince1970: 2)])
        #expect(disk.load().map(\.folder.path) == ["/Users/ada/b", "/Users/ada/c", "/Users/ada/d"])
    }

    @Test func leavesOutGoneFoldersTheHomeTheRootAndWorktrees() {
        let disk = FakeDisk(configuration: Self.configuration(["/Users/ada", "/", "/Users/ada/gone",
                                                               "/Users/ada/worktree", "/Users/ada/repo", "relative"]),
                            folders: ["/Users/ada", "/", "/Users/ada/worktree", "/Users/ada/repo",
                                      "/Users/ada/repo/.git"],
                            files: ["/Users/ada/worktree/.git"])
        #expect(disk.load() == [RecentProject(folder: URL(filePath: "/Users/ada/repo", directoryHint: .isDirectory),
                                              isProtected: false)])
    }

    @Test(arguments: ["/Users/ada/Desktop/sito", "/Users/ada/Documents/tesi", "/Users/ada/Downloads/demo",
                      "/Users/ada/Library/Mobile Documents/com~apple~CloudDocs/app", "/Volumes/Disco/progetto"])
    func neverTouchesProtectedFolders(path: String) throws {
        let disk = FakeDisk(configuration: Self.configuration([path]))
        let project = try #require(disk.load().first)
        #expect(project.isProtected)
        #expect(project.folder.path == path)
        let protected = ["/Users/ada/Desktop", "/Users/ada/Documents", "/Users/ada/Downloads",
                         "/Users/ada/Library/Mobile Documents", "/Volumes"]
        #expect(disk.touched.withLock { $0 }.allSatisfy { touched in !protected.contains { touched.hasPrefix($0) } })
    }

    @Test func noFileOrNoProjectsIsEmpty() {
        #expect(FakeDisk(configuration: "").load().isEmpty)
        #expect(FakeDisk(configuration: #"{"theme": "dark"}"#).load().isEmpty)
        #expect(FakeDisk(configuration: #"{"projects": []}"#).load().isEmpty)
    }

    @Test func encodesEveryCharacterThatIsNotAnASCIILetterOrDigit() {
        #expect(RecentProjects.encodedName(of: "/Users/a_b/my.app è") == "-Users-a-b-my-app--")
    }
}
