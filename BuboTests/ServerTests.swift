import Foundation
import Testing
@testable import Bubo

/// The servers of the Sessioni: found with `libproc` after an event, never at rest, and attributed by folder, then
/// by port (spec 15).
@MainActor
@Suite(.serialized)
struct ServerTests {
    let root: URL
    let first: ServerAttribution.Owner
    let second: ServerAttribution.Owner

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "ServerTests-\(UUID().uuidString)")
        for name in ["a", "b", "altrove"] {
            try FileManager.default.createDirectory(at: root.appending(path: name), withIntermediateDirectories: true)
        }
        first = ServerAttribution.Owner(id: UUID(), folder: root.appending(path: "a"), ports: 47_100..<47_110)
        second = ServerAttribution.Owner(id: UUID(), folder: root.appending(path: "b"), ports: 47_110..<47_120)
    }

    /// `nc` listening on `port` in `folder`, as a dev server would.
    private func listen(on port: Int, in folder: URL) throws -> Process {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/nc")
        process.arguments = ["-l", String(port)]
        process.currentDirectoryURL = folder
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        return process
    }

    @Test func aSocketBelongsToTheSessioneThatHoldsItsFolderThenToTheOneWithItsPort() {
        let owners = [first, second]
        let inA = ListeningSocket(pid: 1, port: 3_000, folder: first.folder + "/web")
        let onPortOfB = ListeningSocket(pid: 2, port: 47_111, folder: "/Applications/Docker.app")
        let inAOnPortOfB = ListeningSocket(pid: 3, port: 47_112, folder: first.folder)
        let elsewhere = ListeningSocket(pid: 4, port: 5_000, folder: first.folder + "-copia")
        #expect(ServerAttribution.owner(of: inA, among: owners) == first.id)
        #expect(ServerAttribution.owner(of: onPortOfB, among: owners) == second.id)
        #expect(ServerAttribution.owner(of: inAOnPortOfB, among: owners) == first.id)
        #expect(ServerAttribution.owner(of: elsewhere, among: owners) == nil)
    }

    @Test func theDeepestFolderWins() {
        let checkout = ServerAttribution.Owner(id: UUID(), folder: root, ports: nil)
        let socket = ListeningSocket(pid: 1, port: 3_000, folder: first.folder)
        #expect(ServerAttribution.owner(of: socket, among: [checkout, first]) == first.id)
    }

    @Test func nothingIsScannedAtRest() async throws {
        let watcher = PortWatcher()
        try await Task.sleep(for: .milliseconds(300))
        #expect(watcher.scanCount == 0)
    }

    @Test func serversAreFoundWithinASecondAndAttributedToTheRightSessione() async throws {
        let watcher = PortWatcher()
        watcher.owners = { [first, second] in [first, second] }
        // Both Sessioni start the same server on their PORT; a third listens on a port of the first from elsewhere.
        let servers = try [listen(on: 47_100, in: root.appending(path: "a")),
                           listen(on: 47_110, in: root.appending(path: "b")),
                           listen(on: 47_105, in: root.appending(path: "altrove"))]
        defer { servers.forEach { $0.terminate() } }
        try await Task.sleep(for: .milliseconds(200))
        let start = ContinuousClock.now
        watcher.notice()
        while watcher.servers.count < 2 || watcher.servers[first.id]?.count != 2, ContinuousClock.now - start < .seconds(1) {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(watcher.servers[first.id]?.map(\.port) == [47_100, 47_105])
        #expect(watcher.servers[second.id]?.map(\.port) == [47_110])
        #expect(watcher.scanCount > 0)
    }

    @Test func theLabelGoesWhenTheServerStops() async throws {
        let watcher = PortWatcher()
        watcher.owners = { [first] in [first] }
        let server = try listen(on: 47_101, in: root.appending(path: "a"))
        try await Task.sleep(for: .milliseconds(200))
        watcher.notice()
        try await Task.sleep(for: .milliseconds(400))
        #expect(watcher.servers[first.id]?.map(\.port) == [47_101])
        server.terminate()
        // The exit of the server's process is itself an event.
        try await Task.sleep(for: .milliseconds(500))
        #expect(watcher.servers[first.id] == nil)
    }

    @Test func outputWithALocalURLOrAMarkHintsAtAServer() {
        #expect(CommandMarks.hintsAtServer(ArraySlice(Array("  ➜  Local:   http://localhost:5173/\n".utf8))))
        #expect(CommandMarks.hintsAtServer(ArraySlice(Array("\u{1B}]133;D;0\u{07}".utf8))))
        #expect(!CommandMarks.hintsAtServer(ArraySlice(Array("compiled 12 files\n".utf8))))
    }

    @Test func launchJSONGivesTheCommandAndItsFolder() throws {
        let folder = root.appending(path: "a")
        try FileManager.default.createDirectory(at: folder.appending(path: ".claude"), withIntermediateDirectories: true)
        try #"""
        {
          // Claude desktop's format, with comments
          "version": "0.0.1",
          "configurations": [
            { "name": "web", "runtimeExecutable": "npm", "runtimeArgs": ["run", "dev"], "cwd": "apps/web", "port": 3000 },
            { "name": "api", "program": "server.js", "args": ["--name", "it's"] },
            { "name": "attached", "url": "https://app.localhost:3000" }
          ]
        }
        """#.write(to: folder.appending(path: ".claude/launch.json"), atomically: true, encoding: .utf8)
        let servers = LaunchConfig.read(in: folder)
        #expect(servers.map(\.name) == ["web", "api"])
        #expect(servers.first?.commandLine == "npm run dev")
        #expect(servers.last?.commandLine == #"node server.js --name 'it'\''s'"#)
        #expect(servers.first?.folder(in: folder).path(percentEncoded: false).hasSuffix("a/apps/web/") == true)
    }
}
