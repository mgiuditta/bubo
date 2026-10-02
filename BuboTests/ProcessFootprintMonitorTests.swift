import Darwin
import Foundation
import Testing
@testable import Bubo

struct ProcessFootprintMonitorTests {
    private let session = UUID()

    @Test func aClaudeOver2GBMakesItsSessioneHeavyAtTheNextReading() {
        let monitor = ProcessFootprintMonitor()
        monitor.record([session: ProcessFootprintMonitor.heavyFootprint - 1])
        #expect(monitor.heavySessions.isEmpty)
        monitor.record([session: ProcessFootprintMonitor.heavyFootprint + 1])
        #expect(monitor.heavySessions == [session])
        #expect(ProcessFootprintMonitor.interval == .seconds(30))
    }

    @Test func aHeavySessioneStaysHeavyUntilItFallsUnder1Point5GB() {
        let monitor = ProcessFootprintMonitor()
        monitor.record([session: 3 << 30])
        monitor.record([session: ProcessFootprintMonitor.lightFootprint + 1])
        #expect(monitor.heavySessions == [session])
        monitor.record([session: ProcessFootprintMonitor.lightFootprint - 1])
        #expect(monitor.heavySessions.isEmpty)
    }

    @Test func aSessioneWithoutAClaudeIsNoLongerHeavy() {
        let monitor = ProcessFootprintMonitor()
        monitor.record([session: 3 << 30])
        monitor.record([:])
        #expect(monitor.heavySessions.isEmpty)
        monitor.record([session: 3 << 30])
        monitor.forget(session)
        #expect(monitor.heavySessions.isEmpty)
    }

    @Test func theConversationComesFromSessionIDInEitherForm() {
        #expect(ProcessInspector.conversation(in: ["claude", "--session-id=abc", "--verbose"]) == "abc")
        #expect(ProcessInspector.conversation(in: ["claude", "--session-id", "abc"]) == "abc")
        #expect(ProcessInspector.conversation(in: ["claude", "--resume=abc"]) == nil)
    }

    @Test func aChildIsFoundByItsConversationWithItsFootprint() async throws {
        let child = try ProcessSpawner.spawn(URL(filePath: "/bin/sh"),
                                             arguments: ["-c", "sleep 30; :", "claude", "--session-id=abc"],
                                             environment: [:])
        defer {
            kill(child.pid, SIGKILL)
            Task { _ = await ProcessSpawner.waitForExit(of: child.pid) }
        }
        let found = ProcessInspector.claudeProcesses(of: getpid())
        #expect(found["abc"] == child.pid)
        let footprint = try #require(ProcessInspector.footprint(of: child.pid))
        #expect(footprint > 0)
    }
}
