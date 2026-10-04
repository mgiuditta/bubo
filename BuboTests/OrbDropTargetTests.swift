import Foundation
import Testing
@testable import Bubo

/// What a drop on the Orb becomes: Riunioni from media files, a Riunione from one web link, else Allegati.
struct OrbDropTargetTests {
    @Test func mediaFilesAreRiunioni() {
        let files = [URL(filePath: "/tmp/a.m4a"), URL(filePath: "/tmp/b.mp4")]
        #expect(OrbDropTarget.drop(files: files, links: []) == .meetingFiles(files))
        #expect(OrbDropTarget.drop(files: files, links: []).isTranscription)
    }

    @Test func aWebLinkAloneIsAVideoLink() throws {
        let link = try #require(URL(string: "https://www.youtube.com/watch?v=abc"))
        #expect(OrbDropTarget.drop(files: [], links: [link]) == .videoLink(link))
        #expect(OrbDropTarget.drop(files: [], links: [link]).isTranscription)
    }

    @Test(arguments: ["ftp://example.com/a.mp4", "mailto:a@b.it"])
    func aLinkThatIsNotWebIsAnAllegato(address: String) throws {
        #expect(OrbDropTarget.drop(files: [], links: [try #require(URL(string: address))]) == .attachments)
    }

    @Test func otherFilesAndSeveralLinksAreAllegati() throws {
        #expect(OrbDropTarget.drop(files: [URL(filePath: "/tmp/a.pdf")], links: []) == .attachments)
        let links = try ["https://a.it", "https://b.it"].map { try #require(URL(string: $0)) }
        #expect(OrbDropTarget.drop(files: [], links: links) == .attachments)
        #expect(!OrbDropTarget.Drop.attachments.isTranscription)
    }
}
