import Foundation
import Testing
@testable import Bubo

@Suite(.timeLimit(.minutes(1)))
struct AgentBridgeTests {
    /// A bridge played by `/bin/sh`: `script` reads commands from standard input and writes events.
    static func bridge(_ script: String) -> AgentBridge {
        AgentBridge(executable: URL(filePath: "/bin/sh"), arguments: ["-c", script],
                    environment: ["PATH": "/usr/bin:/bin"])
    }

    /// Reads the id of the first command, then runs `events` with `$id` set.
    static func answering(_ events: String) -> String {
        #"read line; id=$(echo "$line" | sed 's/.*"id":"\([^"]*\)".*/\1/'); "# + events
    }

    static func collect(_ answer: AsyncThrowingStream<String, any Error>) async throws -> String {
        try await answer.reduce("", +)
    }

    @Test func theAnswerStreamsUntilDone() async throws {
        let bridge = Self.bridge(Self.answering(#"""
            echo '{"v":1,"type":"ready"}'
            echo "{\"v\":1,\"type\":\"text\",\"id\":\"$id\",\"text\":\"cia\"}"
            echo "{\"v\":1,\"type\":\"text\",\"id\":\"$id\",\"text\":\"o\"}"
            echo "{\"v\":1,\"type\":\"done\",\"id\":\"$id\"}"
            read _
            """#))
        let answer = try await Self.collect(bridge.ask("Rispondi: ciao", in: URL(filePath: "/tmp")))
        #expect(answer == "ciao")
    }

    @Test func aSilentBridgeDoesNotStallAnother() async throws {
        let silent = Self.bridge("sleep 30")
        let pending = silent.ask("x", in: URL(filePath: "/tmp"))
        let talking = Self.bridge(Self.answering(#"echo "{\"v\":1,\"type\":\"done\",\"id\":\"$id\"}"; read _"#))
        let clock = ContinuousClock()
        let elapsed = try await clock.measure {
            _ = try await Self.collect(talking.ask("x", in: URL(filePath: "/tmp")))
        }
        #expect(elapsed < .seconds(5))
        _ = pending
    }

    @Test func aFailedConversationThrowsItsMessage() async {
        let bridge = Self.bridge(Self.answering(#"""
            echo "{\"v\":1,\"type\":\"error\",\"id\":\"$id\",\"message\":\"limite raggiunto\"}"
            read _
            """#))
        await #expect(throws: AgentBridgeError.failed(message: "limite raggiunto")) {
            try await Self.collect(bridge.ask("x", in: URL(filePath: "/tmp")))
        }
    }

    @Test func aBridgeThatExitsFailsThePendingAnswer() async {
        let bridge = Self.bridge("read _; exit 3")
        await #expect(throws: AgentBridgeError.bridgeExited(status: 3)) {
            try await Self.collect(bridge.ask("x", in: URL(filePath: "/tmp")))
        }
    }

    @Test func anotherProtocolVersionFailsThePendingAnswer() async {
        let bridge = Self.bridge(#"read _; echo '{"v":2,"type":"ready"}'; read _"#)
        await #expect(throws: AgentBridgeError.unsupportedVersion(2)) {
            try await Self.collect(bridge.ask("x", in: URL(filePath: "/tmp")))
        }
    }

    @Test func aMissingExecutableFailsToSpawn() async {
        let bridge = AgentBridge(executable: URL(filePath: "/nonexistent/bubo-agent"), environment: [:])
        await #expect(throws: AgentBridgeError.spawnFailed(errno: ENOENT)) {
            try await Self.collect(bridge.ask("x", in: URL(filePath: "/tmp")))
        }
    }
}
