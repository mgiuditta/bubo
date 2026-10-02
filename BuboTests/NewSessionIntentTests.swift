import Foundation
import Testing
@testable import Bubo

@MainActor
@Suite(.serialized)
struct NewSessionIntentTests {
    /// Records what "Nuova Sessione" asks, in place of the Sessioni of the HUD.
    @MainActor final class RecordingStarter: SessionStarting {
        var projects: [URL] = []
        var trusted = true
        private(set) var started: [(request: String, project: URL)] = []
        private(set) var askedTrust: [(request: String, project: URL)] = []
        private(set) var reports: [String] = []

        func isTrusted(_ project: URL) -> Bool { trusted }
        func startSession(_ request: String, in project: URL) throws { started.append((request, project)) }
        func askTrust(toStart request: String, in project: URL) { askedTrust.append((request, project)) }
        func report(_ message: String) { reports.append(message) }
    }

    let starter = RecordingStarter()
    let folder = FileManager.default.temporaryDirectory

    init() {
        NewSessionIntent.starter = starter
    }

    func intent(_ text: String, on project: URL) -> NewSessionIntent {
        let intent = NewSessionIntent()
        intent.project = ProjectEntity(folder: project)
        intent.text = text
        return intent
    }

    @Test func aTrustedProgettoStartsTheSessione() async throws {
        _ = try await intent("  Correggi il login  ", on: folder).perform()

        let started = try #require(starter.started.first)
        #expect(starter.started.count == 1)
        #expect(started.request == "Correggi il login")
        #expect(started.project.standardizedFileURL == folder.standardizedFileURL)
        #expect(starter.askedTrust.isEmpty)
    }

    @Test func aProgettoNotTrustedAsksForTrustFirst() async throws {
        starter.trusted = false
        _ = try await intent("Correggi il login", on: folder).perform()

        #expect(starter.started.isEmpty)
        #expect(starter.askedTrust.map(\.request) == ["Correggi il login"])
    }

    @Test func aProgettoThatIsGoneStartsNothingAndTellsThePanel() async {
        let gone = URL(filePath: "/tmp/bubo-sparito-\(UUID().uuidString)", directoryHint: .isDirectory)
        await #expect(throws: NewSessionError.projectMissing(gone.lastPathComponent)) {
            _ = try await intent("Correggi il login", on: gone).perform()
        }

        #expect(starter.started.isEmpty)
        #expect(starter.askedTrust.isEmpty)
        #expect(starter.reports.count == 1)
        #expect(starter.reports.first?.contains(gone.lastPathComponent) == true)
    }

    @Test func aBlankTextStartsNothing() async {
        await #expect(throws: (any Error).self) {
            _ = try await intent(" \n ", on: folder).perform()
        }
        #expect(starter.started.isEmpty)
    }

    @Test func theProgettiOfferedAreTheKnownOnes() async throws {
        starter.projects = [folder]
        let offered = try await ProjectQuery().suggestedEntities()
        #expect(offered.map(\.folder.standardizedFileURL) == [folder.standardizedFileURL])
    }
}
