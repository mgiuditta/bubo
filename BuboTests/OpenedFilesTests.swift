import Foundation
import Testing
@testable import Bubo

struct OpenedFilesTests {
    let bubo = URL(filePath: "/Users/io/dev/bubo", directoryHint: .isDirectory)
    let sito = URL(filePath: "/Users/io/dev/sito", directoryHint: .isDirectory)

    /// Every URL without an extension is a folder, as the Finder hands them.
    func opened(_ paths: [String], projects: [URL]) -> OpenedFiles {
        OpenedFiles(paths.map { URL(filePath: $0) }, projects: projects) { $0.pathExtension.isEmpty }
    }

    @Test func aKnownProgettoOpensAsItIsKept() {
        let files = opened(["/Users/io/dev/bubo/"], projects: [sito, bubo])
        #expect(files.folder == .project(bubo))
        #expect(files.buboFiles.isEmpty)
    }

    @Test func aFolderThatIsNoProgettoCreatesOne() {
        let files = opened(["/Users/io/dev/nuovo"], projects: [bubo])
        #expect(files.folder == .newProject(URL(filePath: "/Users/io/dev/nuovo")))
    }

    @Test func aFolderInsideAProgettoIsANewProgetto() {
        let files = opened(["/Users/io/dev/bubo/Packages"], projects: [bubo])
        #expect(files.folder == .newProject(URL(filePath: "/Users/io/dev/bubo/Packages")))
    }

    @Test func onlyTheFirstOfMoreFoldersCounts() {
        let files = opened(["/Users/io/dev/sito", "/Users/io/dev/bubo"], projects: [bubo, sito])
        #expect(files.folder == .project(sito))
    }

    @Test func buboFilesAreKeptAlongsideTheFolder() {
        let files = opened(["/Users/io/Downloads/consegna.bubo", "/Users/io/dev/bubo", "/Users/io/Downloads/biglietto.BUBO"],
                           projects: [bubo])
        #expect(files.buboFiles.map(\.lastPathComponent) == ["consegna.bubo", "biglietto.BUBO"])
        #expect(files.folder == .project(bubo))
    }

    @Test func otherFilesAndLinksAreIgnored() {
        let urls = [URL(filePath: "/Users/io/note.txt"), URL(string: "bubo://draft?title=x")!]
        let files = OpenedFiles(urls, projects: [bubo]) { $0.pathExtension.isEmpty }
        #expect(files == OpenedFiles([], projects: [bubo]))
    }

    @Test func aFolderOnDiskIsAFolderAndAFileIsNot() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "cartella-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "note.txt")
        try Data("ciao".utf8).write(to: file)

        #expect(OpenedFiles.isFolder(URL(filePath: folder.path(percentEncoded: false))))
        #expect(!OpenedFiles.isFolder(file))
    }
}
