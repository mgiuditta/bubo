import AppKit
import Foundation
import Testing
@testable import Bubo

/// Who receives which Allegato (spec 09), and what a drop on the Orb turns into.
struct AttachmentPolicyTests {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "AttachmentPolicyTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    /// A file named `name` in the test's folder, with `data` in it.
    func file(_ name: String, _ data: Data) throws -> URL {
        let url = folder.appending(path: name)
        try data.write(to: url)
        return url
    }

    @Test func claudeReceivesEveryAllegato() throws {
        let attachments = [
            Allegato(name: "Nota", text: "Testo"),
            Allegato(fileAt: try file("main.swift", Data("let x = 1".utf8))),
            Allegato(fileAt: folder),
            Allegato(fileAt: try file("Schermata.png", Data([0x89, 0x50, 0x4E, 0x47]))),
        ]
        #expect(attachments.allSatisfy { AttachmentPolicy.allows($0, to: .claude) })
    }

    @Test func theMacReadsOnlyText() throws {
        let note = Allegato(fileAt: try file("nota.md", Data("# Titolo".utf8)))
        #expect(note.kind == .file)
        #expect(note.text == "# Titolo")
        #expect(AttachmentPolicy.allows(note, to: .onDevice))
        #expect(AttachmentPolicy.allows(Allegato(name: "Nota", text: "Testo"), to: .onDevice))

        let binary = Allegato(fileAt: try file("archivio.zip", Data([0x50, 0x4B, 0x03, 0x04])))
        #expect(binary.text == nil)
        #expect(!AttachmentPolicy.allows(binary, to: .onDevice))
    }

    @Test func aFolderGoesOnlyToClaude() {
        let allegato = Allegato(fileAt: folder)
        #expect(allegato.kind == .folder)
        #expect(allegato.path == folder)
        #expect(AttachmentPolicy.allows(allegato, to: .claude))
        #expect(!AttachmentPolicy.allows(allegato, to: .onDevice))
        #expect(!AttachmentPolicy.allows(allegato, to: .otherProvider))
    }

    @Test func aScreenshotGoesOnlyToClaude() throws {
        let allegato = Allegato(fileAt: try file("Schermata.png", Data([0x89, 0x50, 0x4E, 0x47])))
        #expect(allegato.kind == .image)
        #expect(AttachmentPolicy.allows(allegato, to: .claude))
        #expect(!AttachmentPolicy.allows(allegato, to: .onDevice))
        #expect(!AttachmentPolicy.allows(allegato, to: .otherProvider))
    }

    // Until #99 asks for consent, nothing goes to another provider.
    @Test func noAllegatoGoesToAnotherProviderWithoutConsent() {
        #expect(!AttachmentPolicy.allows(Allegato(name: "Nota", text: "Testo"), to: .otherProvider))
    }

    @Test func aTextFileOverTheReadableSizeIsNotRead() throws {
        let long = Data(repeating: UInt8(ascii: "a"), count: Allegato.readableSize + 1)
        let allegato = Allegato(fileAt: try file("lungo.txt", long))
        #expect(allegato.text == nil)
        #expect(!AttachmentPolicy.allows(allegato, to: .onDevice))
    }

    @Test func aRichiestaWithAFolderIsNotReadOnTheMac() {
        #expect(Richiesta(text: "Riassumi", attachments: [Allegato(name: "Nota", text: "Testo")]).isReadableOnDevice)
        #expect(!Richiesta(text: "Riassumi", attachments: [Allegato(fileAt: folder)]).isReadableOnDevice)
    }

    @Test func draggedTextIsNamedAfterItsFirstWords() {
        let allegato = Allegato(draggedText: "Una riga abbastanza lunga da essere accorciata nel nome\nseconda")
        #expect(allegato.name == "Una riga abbastanza lunga da ess…")
        #expect(allegato.text == "Una riga abbastanza lunga da essere accorciata nel nome\nseconda")
        #expect(allegato.path == nil)
    }

    @MainActor @Test func aDropOfFilesKeepsTheirPaths() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("AttachmentPolicyTests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let note = try file("nota.txt", Data("ciao".utf8))
        pasteboard.clearContents()
        pasteboard.writeObjects([note as NSURL, folder as NSURL])
        let attachments = OrbDropTarget.attachments(from: pasteboard, imageDirectory: folder)
        #expect(attachments.map(\.kind) == [.file, .folder])
        #expect(attachments.map { $0.path?.resolvingSymlinksInPath().path(percentEncoded: false) }
            == [note, folder].map { $0.resolvingSymlinksInPath().path(percentEncoded: false) })
    }

    @MainActor @Test func aDropOfAnImageIsSavedForClaude() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("AttachmentPolicyTests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let image = NSImage(size: CGSize(width: 2, height: 2), flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            return true
        }
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        let attachments = OrbDropTarget.attachments(from: pasteboard, imageDirectory: folder)
        let allegato = try #require(attachments.first)
        #expect(attachments.count == 1)
        #expect(allegato.kind == .image)
        let path = try #require(allegato.path)
        #expect(path.resolvingSymlinksInPath().path(percentEncoded: false)
            .hasPrefix(folder.resolvingSymlinksInPath().path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: path.path(percentEncoded: false)))
    }

    @MainActor @Test func aDropOfAnAddressOrATextGoesAsText() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("AttachmentPolicyTests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.writeObjects([URL(string: "https://example.com/pagina")! as NSURL])
        #expect(OrbDropTarget.attachments(from: pasteboard, imageDirectory: folder)
            == [Allegato(name: "example.com", text: "https://example.com/pagina")])

        pasteboard.clearContents()
        pasteboard.setString("Testo scelto", forType: .string)
        #expect(OrbDropTarget.attachments(from: pasteboard, imageDirectory: folder)
            == [Allegato(name: "Testo scelto", text: "Testo scelto")])

        pasteboard.clearContents()
        pasteboard.setString("   ", forType: .string)
        #expect(OrbDropTarget.attachments(from: pasteboard, imageDirectory: folder).isEmpty)
    }

    @Test func claudeReadsFilesFromTheirPathAndTextInline() throws {
        let note = try file("nota.txt", Data("ciao".utf8))
        let prompt = QuestionModel.prompt("Che cosa dicono?", attachments: [
            Allegato(name: "Citazione", text: "Testo scelto"),
            Allegato(fileAt: note),
            Allegato(fileAt: folder),
        ])
        #expect(prompt == """
            Che cosa dicono?

            --- Citazione ---
            Testo scelto

            Allegati da leggere dal disco:
            - \(note.path(percentEncoded: false))
            - \(folder.path(percentEncoded: false))
            """)
        #expect(QuestionModel.readableDirectories(for: [Allegato(fileAt: note), Allegato(fileAt: folder)])
            == [URL(filePath: folder.path(percentEncoded: false), directoryHint: .isDirectory)])
    }
}
