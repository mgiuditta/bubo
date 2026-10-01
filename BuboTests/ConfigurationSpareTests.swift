import Dispatch
import Foundation
import Testing
@testable import Bubo

struct ConfigurationSpareTests {
    /// What the policy asked of the bridge, in order.
    enum Command: Equatable {
        case warm(URL)
        case cool
    }

    final class Bridge {
        var commands: [Command] = []
    }

    static let newest = URL(filePath: "/tmp/nuovo", directoryHint: .isDirectory)
    static let other = URL(filePath: "/tmp/altro", directoryHint: .isDirectory)
    static let empty = ClaudeConfiguration(skills: [], plugins: [], pluginErrors: [], mcpServers: [], instructions: [])

    let bridge = Bridge()

    func spare(delay: Duration = .zero, project: URL? = newest) -> ConfigurationSpare {
        ConfigurationSpare(delay: delay) { project } warm: { [bridge] in
            bridge.commands.append(.warm($0))
        } cool: { [bridge] in
            bridge.commands.append(.cool)
        }
    }

    /// Starts `spare` and waits until the bridge got what it asked.
    func launch(_ spare: ConfigurationSpare) async {
        spare.startAfterLaunch()
        await spare.launch?.value
        await spare.lastCommand?.value
    }

    func read(_ project: URL, with spare: ConfigurationSpare) async throws {
        _ = try await spare.configuration(of: project) { _ in Self.empty }
        await spare.lastCommand?.value
    }

    @Test func nothingStartsBeforeTheDelay() async throws {
        let spare = spare(delay: .seconds(3600))
        spare.startAfterLaunch()
        try await read(Self.newest, with: spare)
        spare.launch?.cancel()
        await spare.launch?.value

        #expect(bridge.commands.isEmpty)
    }

    @Test func afterTheDelayItStartsForTheNewestProgetto() async {
        let spare = spare()
        await launch(spare)
        await launch(spare)

        #expect(bridge.commands == [.warm(Self.newest)])
    }

    @Test func withNoProgettoNothingStarts() async {
        let spare = spare(project: nil)
        await launch(spare)

        #expect(bridge.commands.isEmpty)
    }

    @Test func eachReadUsesItUpAndAnotherStartsForTheProgettoShown() async throws {
        let spare = spare()
        await launch(spare)

        try await read(Self.other, with: spare)
        try await read(Self.other, with: spare)

        #expect(bridge.commands == [.warm(Self.newest), .warm(Self.other), .warm(Self.other)])
    }

    @Test func aFailedReadAlsoStartsAnother() async {
        let spare = spare()
        await launch(spare)

        await #expect(throws: AgentBridgeError.failed(message: "no")) {
            try await spare.configuration(of: Self.newest) { _ in throw AgentBridgeError.failed(message: "no") }
        }
        await spare.lastCommand?.value

        #expect(bridge.commands == [.warm(Self.newest), .warm(Self.newest)])
    }

    @Test func memoryPressureClosesItUntilItIsOver() async throws {
        let spare = spare()
        await launch(spare)

        spare.memoryPressureChanged(to: .warning)
        spare.memoryPressureChanged(to: .critical)
        try await read(Self.newest, with: spare)
        await spare.lastCommand?.value
        #expect(bridge.commands == [.warm(Self.newest), .cool])

        spare.memoryPressureChanged(to: .normal)
        await spare.lastCommand?.value
        #expect(bridge.commands == [.warm(Self.newest), .cool, .warm(Self.newest)])
    }
}
