import Foundation
import Testing
@testable import Bubo

@Suite(.timeLimit(.minutes(1)))
struct AgentBridgeTests {
    /// A bridge played by `/bin/sh`: `script` reads commands from standard input and writes events.
    static func bridge(_ script: String) -> AgentBridge {
        AgentBridge(executable: URL(filePath: "/bin/sh"), arguments: ["-c", script],
                    environment: ["PATH": "/usr/bin:/bin"]) { query, project in "\(query) in \(project ?? "tutto")" }
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
            echo '{"v":3,"type":"ready"}'
            echo "{\"v\":3,\"type\":\"text\",\"id\":\"$id\",\"text\":\"cia\"}"
            echo "{\"v\":3,\"type\":\"text\",\"id\":\"$id\",\"text\":\"o\"}"
            echo "{\"v\":3,\"type\":\"done\",\"id\":\"$id\"}"
            read _
            """#))
        let answer = try await Self.collect(bridge.ask("Rispondi: ciao", in: URL(filePath: "/tmp")))
        #expect(answer == "ciao")
    }

    @Test func aSearchIsAnsweredOnTheBridgesInput() async throws {
        // The answer to the search comes back as the conversation's text, so the test can read it.
        let bridge = Self.bridge(Self.answering(#"""
            echo '{"v":3,"type":"search","id":"s1","query":"notarizzazione","project":"/p"}'
            read found
            text=$(echo "$found" | sed 's/.*"text":"\([^"]*\)".*/\1/')
            echo "{\"v\":3,\"type\":\"text\",\"id\":\"$id\",\"text\":\"$text\"}"
            echo "{\"v\":3,\"type\":\"done\",\"id\":\"$id\"}"
            read _
            """#))
        let answer = try await Self.collect(bridge.ask("x", in: URL(filePath: "/tmp")))
        #expect(answer == "notarizzazione in /p")
    }

    @Test func theProgressArrivesBeforeTheAnswerEndsAndNotAfter() async throws {
        let bridge = Self.bridge(Self.answering(#"""
            echo "{\"v\":3,\"type\":\"state\",\"id\":\"$id\",\"state\":\"running\"}"
            echo "{\"v\":3,\"type\":\"summary\",\"id\":\"$id\",\"text\":\"Leggo i file\"}"
            echo "{\"v\":3,\"type\":\"state\",\"id\":\"$id\",\"state\":\"idle\"}"
            echo "{\"v\":3,\"type\":\"done\",\"id\":\"$id\"}"
            echo "{\"v\":3,\"type\":\"state\",\"id\":\"$id\",\"state\":\"running\"}"
            read line; id=$(echo "$line" | sed 's/.*"id":"\([^"]*\)".*/\1/')
            echo "{\"v\":3,\"type\":\"done\",\"id\":\"$id\"}"
            read _
            """#))
        var received: [AgentProgress] = []
        _ = try await Self.collect(bridge.ask("x", in: URL(filePath: "/tmp")) { received.append($0) })
        // A second answer: once it ends, the bridge has read the late `running` of the first.
        _ = try await Self.collect(bridge.ask("y", in: URL(filePath: "/tmp")))
        #expect(received == [.state(.running), .summary("Leggo i file"), .state(.idle)])
    }

    @Test func aSilentBridgeDoesNotStallAnother() async throws {
        let silent = Self.bridge("sleep 30")
        let pending = silent.ask("x", in: URL(filePath: "/tmp"))
        let talking = Self.bridge(Self.answering(#"echo "{\"v\":3,\"type\":\"done\",\"id\":\"$id\"}"; read _"#))
        let clock = ContinuousClock()
        let elapsed = try await clock.measure {
            _ = try await Self.collect(talking.ask("x", in: URL(filePath: "/tmp")))
        }
        #expect(elapsed < .seconds(5))
        _ = pending
    }

    @Test func aFailedConversationThrowsItsMessage() async {
        let bridge = Self.bridge(Self.answering(#"""
            echo "{\"v\":3,\"type\":\"error\",\"id\":\"$id\",\"message\":\"limite raggiunto\"}"
            read _
            """#))
        await #expect(throws: AgentBridgeError.failed(message: "limite raggiunto")) {
            try await Self.collect(bridge.ask("x", in: URL(filePath: "/tmp")))
        }
    }

    @Test func aLimitFailsTheConversationWithItsWindowAndReset() async {
        let bridge = Self.bridge(Self.answering(#"""
            echo "{\"v\":3,\"type\":\"limit\",\"id\":\"$id\",\"window\":\"seven_day\",\"resetsAt\":1791428400}"
            read _
            """#))
        await #expect(throws: AgentBridgeError.limitReached(
            Quota.Limit(window: "seven_day", resetsAt: Date(timeIntervalSince1970: 1_791_428_400)))) {
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
        let bridge = Self.bridge(#"read _; echo '{"v":4,"type":"ready"}'; read _"#)
        await #expect(throws: AgentBridgeError.unsupportedVersion(4)) {
            try await Self.collect(bridge.ask("x", in: URL(filePath: "/tmp")))
        }
    }

    @Test func theQuotaIsReadWithoutADomanda() async throws {
        let (reports, reported) = AsyncStream.makeStream(of: Quota.self)
        let bridge = AgentBridge(executable: URL(filePath: "/bin/sh"), arguments: ["-c", #"""
            read command
            echo "$command" | grep -q '"type":"quota"' \
                && echo '{"v":3,"type":"quota","fiveHour":{"used":0.19,"resetsAt":1790852400}}'
            read _
            """#], environment: ["PATH": "/usr/bin:/bin"], quota: { reported.yield($0) }) { _, _ in "" }
        try bridge.readQuota()
        var iterator = reports.makeAsyncIterator()
        let quota = await iterator.next()
        #expect(quota == Quota(fiveHour: Quota.Window(used: 0.19, resetsAt: Date(timeIntervalSince1970: 1_790_852_400))))
    }

    @Test func theConfigurationIsReadWithTheFoldersSources() async throws {
        // Echoes the sources it was asked with as the only skill, so the test can read them.
        let bridge = Self.bridge(Self.answering(#"""
            sources=$(echo "$line" | grep -q '"type":"config"' && echo "$line" | sed 's/.*"settingSources":\(\[[^]]*\]\).*/\1/')
            echo "{\"v\":3,\"type\":\"config\",\"id\":\"$id\",\"skills\":$sources,\"plugins\":[],\"pluginErrors\":[],\"mcpServers\":[],\"instructions\":[]}"
            read _
            """#))
        let configuration = try await bridge.configuration(of: URL(filePath: "/nonexistent/progetto"))
        #expect(configuration.skills == ["user"])
        #expect(!configuration.loadsProject)
    }

    @Test func aFailedInspectionThrowsItsMessage() async {
        let bridge = Self.bridge(Self.answering(#"""
            echo "{\"v\":3,\"type\":\"error\",\"id\":\"$id\",\"message\":\"claude non ha mandato init\"}"
            read _
            """#))
        await #expect(throws: AgentBridgeError.failed(message: "claude non ha mandato init")) {
            try await bridge.configuration(of: URL(filePath: "/tmp"))
        }
    }

    @Test func aBridgeThatExitsFailsThePendingInspection() async {
        let bridge = Self.bridge("read _; exit 3")
        await #expect(throws: AgentBridgeError.bridgeExited(status: 3)) {
            try await bridge.configuration(of: URL(filePath: "/tmp"))
        }
    }

    @Test func aForkCarriesTheConversationItResumes() async throws {
        // Echoes the conversation it was asked to resume, so the test can read it.
        let bridge = Self.bridge(Self.answering(#"""
            resume=$(echo "$line" | sed 's/.*"resume":"\([^"]*\)".*/\1/')
            echo "{\"v\":3,\"type\":\"text\",\"id\":\"$id\",\"text\":\"$resume\"}"
            echo "{\"v\":3,\"type\":\"done\",\"id\":\"$id\"}"
            read _
            """#))
        let answer = try await Self.collect(bridge.ask("x", in: URL(filePath: "/tmp"), forkingFrom: "c-1"))
        #expect(answer == "c-1")
    }

    @Test func theHistoryIsReadWhole() async throws {
        let bridge = Self.bridge(Self.answering(#"""
            echo "$line" | grep -q '"all":true' \
                && echo "{\"v\":3,\"type\":\"history\",\"id\":\"$id\",\"conversations\":[{\"id\":\"c-1\",\"title\":\"Prova\",\"lastModified\":0}]}"
            read _
            """#))
        let history = try await bridge.history(isComplete: true)
        #expect(history.map(\.id) == ["c-1"])
    }

    @Test func aTranscriptIsReadForItsConversation() async throws {
        let bridge = Self.bridge(Self.answering(#"""
            echo "$line" | grep -q '"conversation":"c-1"' \
                && echo "{\"v\":3,\"type\":\"transcript\",\"id\":\"$id\",\"messages\":[{\"role\":\"user\",\"text\":\"Ciao\"}]}"
            read _
            """#))
        let messages = try await bridge.transcript(of: "c-1")
        #expect(messages == [CLIConversation.Message(isFromUser: true, text: "Ciao")])
    }

    @Test func aMissingExecutableFailsToSpawn() async {
        let bridge = AgentBridge(executable: URL(filePath: "/nonexistent/bubo-agent"), environment: [:]) { _, _ in "" }
        await #expect(throws: AgentBridgeError.spawnFailed(errno: ENOENT)) {
            try await Self.collect(bridge.ask("x", in: URL(filePath: "/tmp")))
        }
    }

    /// A bridge that asks one permission of the conversation, then writes Bubo's answer back as the conversation's text.
    static let askingPermission = answering(#"""
        echo "{\"v\":3,\"type\":\"permission\",\"id\":\"$id\",\"request\":\"p1\",\"tool\":\"Bash\",\"command\":\"npm test\"}"
        read answer
        behavior=$(echo "$answer" | sed 's/.*"behavior":"\([^"]*\)".*/\1/')
        echo "{\"v\":3,\"type\":\"text\",\"id\":\"$id\",\"text\":\"$behavior\"}"
        echo "{\"v\":3,\"type\":\"done\",\"id\":\"$id\"}"
        read _
        """#)

    @Test func aPermissionIsAnsweredOnTheBridgesInput() async throws {
        let bridge = Self.bridge(Self.askingPermission)
        var asked: [PermissionEvent] = []
        let answer = try await Self.collect(bridge.ask("x", in: URL(filePath: "/tmp"), permissions: { event in
            asked.append(event)
            if case let .asked(request) = event { bridge.answerPermission(request.id, allows: true) }
        }))
        #expect(answer == "allow")
        #expect(asked == [.asked(PermissionRequest(id: "p1", tool: "Bash", command: "npm test"))])
    }

    @Test func aConversationThatTakesNoPermissionsIsDenied() async throws {
        let bridge = Self.bridge(Self.askingPermission)
        let answer = try await Self.collect(bridge.ask("x", in: URL(filePath: "/tmp")))
        #expect(answer == "deny")
    }
}
