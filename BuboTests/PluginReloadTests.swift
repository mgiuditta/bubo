import Foundation
import Synchronization
import Testing
@testable import Bubo

/// Ricarica plugin for the turns in progress (spec 20, #212): generation, `held` and Ricarica comunque, Ricarica tutte.
/// `claude`, the bridge and the plugin CLI are fakes.
@MainActor
struct PluginReloadTests {
    /// A bridge played by `/bin/sh` that writes every command to `$1` and keeps each turn going until it is cancelled.
    /// Ricarica plugin is held the first time, with a server it would add; Ricarica comunque applies it, and the turn
    /// then has the plugin's command `linear:issue`.
    static func reloadingBridge(log: URL) -> AgentBridge {
        let script = #"""
            while read line; do
                echo "$line" >> "$1"
                id=$(echo "$line" | sed 's/.*"id":"\([^"]*\)".*/\1/')
                case "$line" in
                    *'"type":"ask"'*) turn=$id ;;
                    *'"type":"cancel"'*) echo "{\"v\":4,\"type\":\"done\",\"id\":\"$turn\"}" ;;
                    *'"type":"reloadPlugins"'*)
                        case "$line" in
                            *"\"turn\":\"$turn\""*) ;;
                            *) echo "{\"v\":4,\"type\":\"error\",\"id\":\"$id\",\"message\":\"turno finito\"}"; continue ;;
                        esac
                        case "$line" in
                            *'"force":true'*) echo "{\"v\":4,\"type\":\"pluginsReloaded\",\"id\":\"$id\",\"commands\":[\"review\",\"linear:issue\"],\"held\":false}" ;;
                            *) echo "{\"v\":4,\"type\":\"pluginsReloaded\",\"id\":\"$id\",\"commands\":[\"review\"],\"held\":true,\"cacheImpact\":{\"added\":[\"plugin:linear:linear\"],\"removed\":[],\"lsp\":\"may-add\"}}" ;;
                        esac ;;
                esac
            done
            """#
        return AgentBridge(executable: URL(filePath: "/bin/sh"), arguments: ["-c", script, "sh", log.path],
                           environment: ["PATH": "/usr/bin:/bin"]) { _, _, _ in "" }
    }

    @Test func aTurnInProgressGetsRicaricaAndAHeldReloadAsksToReloadAnyway() async throws {
        let log = URL.temporaryDirectory.appending(path: "bridge-\(UUID().uuidString).log")
        let file = URL.temporaryDirectory.appending(path: "Sessioni-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: log)
            try? FileManager.default.removeItem(at: file)
        }
        let bridge = Self.reloadingBridge(log: log)
        let store = SessionStore(file: file, worktrees: WorktreeManager(root: URL.temporaryDirectory)) { bridge }
        let reloader = store.pluginReloader
        let id = try store.start("Lavora", title: "Prova", branch: "", in: URL(filePath: "/tmp"), onCheckout: true)
        try await waitForCondition { store.sessions.first?.conversations.count == 1 }
        #expect(reloader.state(of: id) == nil)

        reloader.pluginsDidChange()
        #expect(reloader.state(of: id) == .outdated)
        #expect(reloader.outdatedSessions == [id])

        await reloader.reloadPlugins(in: id)
        let impact = PluginReload.CacheImpact(added: ["plugin:linear:linear"], removed: [], lsp: "may-add")
        #expect(reloader.state(of: id) == .held(impact))

        await reloader.reloadPlugins(in: id)
        #expect(reloader.state(of: id) == nil)
        let reloads = try String(contentsOf: log, encoding: .utf8).split(separator: "\n")
            .filter { $0.contains(#""type":"reloadPlugins""#) }
        #expect(reloads.map { $0.contains(#""force":true"#) } == [false, true])

        // Once the turn ends, the next one loads the plugins by itself: nothing to reload.
        reloader.pluginsDidChange()
        store.interrupt(id)
        try await waitForCondition { store.sessions.first?.isRunning == false }
        #expect(reloader.state(of: id) == nil)
        #expect(reloader.outdatedSessions.isEmpty)
    }

    @Test func afterRicaricaComunqueThePluginsCommandIsThere() async throws {
        let log = URL.temporaryDirectory.appending(path: "bridge-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: log) }
        let bridge = Self.reloadingBridge(log: log)
        let answer = bridge.ask("Lavora", in: URL(filePath: "/tmp"), id: "turno")
        try await waitForCondition { (try? String(contentsOf: log, encoding: .utf8))?.contains(#""type":"ask""#) == true }

        let held = try await bridge.reloadPlugins(ofAnswer: "turno", isForced: false)
        #expect(held.isHeld)
        #expect(!held.commands.contains("linear:issue"))
        let applied = try await bridge.reloadPlugins(ofAnswer: "turno", isForced: true)
        #expect(!applied.isHeld)
        #expect(applied.commands.contains("linear:issue"))
        await #expect(throws: AgentBridgeError.failed(message: "turno finito")) {
            try await bridge.reloadPlugins(ofAnswer: "finito", isForced: false)
        }
        _ = answer
    }

    @Test func ricaricaTutteLeavesTheHeldOnesToTheirOwnButton() async throws {
        let first = UUID(), second = UUID(), held = UUID(), later = UUID()
        let asked = Mutex<[UUID: [Bool]]>([:])
        let reloader = PluginReloader { session, isForced in
            asked.withLock { $0[session, default: []].append(isForced) }
            return PluginReload(commands: [], isHeld: session == held)
        }
        for session in [first, second, held] { reloader.turnDidStart(in: session) }
        reloader.pluginsDidChange()
        // A turn started after the change already has the new plugins.
        reloader.turnDidStart(in: later)
        #expect(reloader.outdatedSessions == [first, second, held])

        await reloader.reloadPlugins(in: held)
        await reloader.reloadAllPlugins()

        #expect(reloader.outdatedSessions == [held])
        #expect(reloader.state(of: held) == .held(nil))
        #expect(asked.withLock { $0 } == [first: [false], second: [false], held: [false]])
        await reloader.reloadPlugins(in: later)
        #expect(asked.withLock { $0[later] } == nil)
    }

    @Test func aFailedReloadOffersRicaricaAgain() async throws {
        let session = UUID()
        let reloader = PluginReloader { _, _ in throw AgentBridgeError.failed(message: "chiuso") }
        reloader.turnDidStart(in: session)
        reloader.pluginsDidChange()

        await reloader.reloadPlugins(in: session)

        #expect(reloader.state(of: session) == .outdated)
    }

    @Test func aCommandThatSucceededChangesThePluginsAndARefusalDoesNot() async throws {
        let succeeds = Mutex(true)
        let cli = PluginCLI(run: { _, _, _ in
            succeeds.withLock { $0 }
                ? ProcessOutput(exitCode: 0, standardOutput: #"{"pluginId": "uno@prova", "saved": ["api_key"], "unconfigured": []}"#)
                : ProcessOutput(exitCode: 1, standardOutput: #"{"pluginId": "uno@prova", "refused": {"option": "count", "message": "No."}}"#)
        }, home: URL.temporaryDirectory, queue: PluginWriteQueue())
        let reloader = PluginReloader()
        let catalog = PluginCatalog(listing: .answering(PluginList()), cli: cli,
                                    pluginsDidChange: { reloader.pluginsDidChange() })
        let plugin = PluginID(name: "uno", marketplace: "prova")
        let command = PluginCommand.configure(plugin, values: PluginOptionValues(["api_key": "x"]))

        #expect(try await catalog.perform(command).succeeded)
        #expect(reloader.generation == 1)
        succeeds.withLock { $0 = false }
        #expect(try await !catalog.perform(command).succeeded)
        #expect(reloader.generation == 1)
    }

    @Test func aChangeSeenOnDiskChangesThePlugins() async throws {
        let home = try PluginHome()
        try home.addMarketplace("ufficiale", plugins: [["name": "revisore", "source": "./plugins/revisore"]])
        let reloader = PluginReloader()
        let catalog = PluginCatalog(folders: home.folders, listing: .answering(PluginList()),
                                    pluginsDidChange: { reloader.pluginsDidChange() })
        let following = Task { await catalog.follow(project: home.project) }
        defer { following.cancel() }
        try await waitForCondition { catalog.snapshot != nil }
        // Time for FSEvents to start, then an installation from the terminal.
        try await Task.sleep(for: .seconds(1))
        try home.install(["revisore@ufficiale": [home.installation()]])

        try await waitForCondition { reloader.generation > 0 }
    }

    @Test func theChangesOnDiskAreFollowedOnlyWhileATurnIsInProgress() async throws {
        let first = UUID(), second = UUID()
        let one = URL(filePath: "/tmp/uno"), two = URL(filePath: "/tmp/due")
        let watches = Mutex<[[URL]]>([]), stopped = Mutex(0)
        let latest = Mutex<AsyncStream<Void>.Continuation?>(nil)
        let reloader = PluginReloader(changes: { folders in
            let (changes, continuation) = AsyncStream.makeStream(of: Void.self)
            continuation.onTermination = { _ in stopped.withLock { $0 += 1 } }
            watches.withLock { $0.append(folders) }
            latest.withLock { $0 = continuation }
            return changes
        })
        #expect(!reloader.isWatching)

        reloader.turnDidStart(in: first, folder: one)
        reloader.turnDidStart(in: second, folder: two)
        #expect(watches.withLock { $0 } == [[one], [two, one]])
        latest.withLock { _ = $0?.yield() }
        try await waitForCondition { reloader.outdatedSessions == [first, second] }

        reloader.turnDidEnd(in: first)
        reloader.turnDidEnd(in: second)
        #expect(!reloader.isWatching)
        try await waitForCondition { stopped.withLock { $0 } == 2 }
    }

    @Test func anInstallationFromTheTerminalWithTheWindowClosedOffersRicarica() async throws {
        let home = try PluginHome()
        try home.addMarketplace("ufficiale", plugins: [["name": "revisore", "source": "./plugins/revisore"]])
        let log = URL.temporaryDirectory.appending(path: "bridge-\(UUID().uuidString).log")
        let file = URL.temporaryDirectory.appending(path: "Sessioni-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: log)
            try? FileManager.default.removeItem(at: file)
        }
        let bridge = Self.reloadingBridge(log: log)
        let store = SessionStore(file: file, worktrees: WorktreeManager(root: URL.temporaryDirectory)) { bridge }
        store.pluginFolders = home.folders
        let reloader = store.pluginReloader
        #expect(!reloader.isWatching)
        let id = try store.start("Lavora", title: "Prova", branch: "", in: home.project, onCheckout: true)
        try await waitForCondition { reloader.isWatching }
        // Time for FSEvents to start, then an installation from the terminal.
        try await Task.sleep(for: .seconds(1))
        try home.install(["revisore@ufficiale": [home.installation()]])

        try await waitForCondition { reloader.state(of: id) == .outdated }
        store.interrupt(id)
        try await waitForCondition { store.sessions.first?.isRunning == false }
        #expect(!reloader.isWatching)
    }

    @Test func theBridgeLinesOfRicaricaPlugin() throws {
        let line = try BridgeCommand.reloadPlugins(id: "r", turn: "t", isForced: true).line()
        let object = try #require(try JSONSerialization.jsonObject(with: line) as? [String: Any])
        #expect(object["type"] as? String == "reloadPlugins")
        #expect(object["turn"] as? String == "t")
        #expect(object["force"] as? Bool == true)
        let first = try BridgeCommand.reloadPlugins(id: "r", turn: "t").line()
        #expect(!String(decoding: first, as: UTF8.self).contains("force"))

        let event = try JSONDecoder().decode(BridgeEvent.self, from: Data(#"""
            {"v":4,"type":"pluginsReloaded","id":"r","commands":["review"],"held":true,"cacheImpact":{"added":[],"removed":["plugin:a:b"]}}
            """#.utf8))
        #expect(event == .pluginsReloaded(id: "r", PluginReload(commands: ["review"], isHeld: true,
                                                                  cacheImpact: .init(added: [], removed: ["plugin:a:b"]))))
    }
}
