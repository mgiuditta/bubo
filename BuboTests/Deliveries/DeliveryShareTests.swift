import AppKit
import Testing
@testable import Bubo

/// The temporary `.bubo` goes when the Condividi of macOS closes, whatever happened.
@MainActor
struct DeliveryShareTests {
    func makeFile() throws -> (file: URL, folder: URL) {
        let folder = URL.temporaryDirectory.appending(path: "DeliveryShareTests-\(UUID().uuidString)",
                                                      directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: "Prova.bubo")
        try Data("BUBO".utf8).write(to: file)
        return (file, folder)
    }

    @Test func closingTheCondividiWithoutAServiceDeletesTheFile() throws {
        let (file, folder) = try makeFile()
        var outcomes: [DeliveryShare.Outcome] = []
        let share = DeliveryShare(file: file, folder: folder) { outcomes.append($0) }

        share.sharingServicePicker(NSSharingServicePicker(items: [file]), didChoose: nil)

        #expect(!FileManager.default.fileExists(atPath: folder.path))
        #expect(outcomes == [.cancelled])
    }

    @Test func sendingOrFailingDeletesTheFileOnce() throws {
        let service = try #require(NSSharingService(named: .sendViaAirDrop) ?? NSSharingService(named: .composeEmail))
        for failing in [false, true] {
            let (file, folder) = try makeFile()
            var outcomes: [DeliveryShare.Outcome] = []
            let share = DeliveryShare(file: file, folder: folder) { outcomes.append($0) }

            if failing {
                share.sharingService(service, didFailToShareItems: [file], error: CocoaError(.userCancelled))
            } else {
                share.sharingService(service, didShareItems: [file])
            }
            share.sharingServicePicker(NSSharingServicePicker(items: [file]), didChoose: nil)

            #expect(!FileManager.default.fileExists(atPath: folder.path))
            #expect(outcomes == [failing ? .failed : .shared(channel: service.title)])
        }
    }
}
