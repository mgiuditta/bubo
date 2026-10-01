import Foundation
import Testing
@testable import Bubo

/// Apri nell'editor: which editor, and the command that opens the file at the line without asking anything (spec 15).
struct EditorTests {
    let worktree = URL(filePath: "/tmp/progetto")
    let location = SourceLocation(file: URL(filePath: "/tmp/progetto/src/main.swift"), line: 42, column: 7)

    private func editor(_ bundleID: String, at path: String) -> Editor {
        Editor(bundleID: bundleID, application: URL(filePath: path))
    }

    @Test func visualStudioCodeOpensTheWorktreeAndGoesToTheLine() {
        let command = editor("com.microsoft.VSCode", at: "/Applications/Visual Studio Code.app")
            .command(opening: location, in: worktree) { _ in true }
        #expect(command.executable.path == "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code")
        #expect(command.arguments == ["/tmp/progetto", "-g", "/tmp/progetto/src/main.swift:42:7"])
    }

    @Test func cursorUsesTheSameArgumentsAsVisualStudioCode() {
        let command = editor("com.todesktop.230313mzl4w4u92", at: "/Applications/Cursor.app")
            .command(opening: location, in: worktree) { _ in true }
        #expect(command.executable.path == "/Applications/Cursor.app/Contents/Resources/app/bin/cursor")
        #expect(command.arguments == ["/tmp/progetto", "-g", "/tmp/progetto/src/main.swift:42:7"])
    }

    @Test func zedTakesFileLineAndColumn() {
        let command = editor("dev.zed.Zed", at: "/Applications/Zed.app")
            .command(opening: location, in: worktree) { _ in true }
        #expect(command.executable.path == "/Applications/Zed.app/Contents/MacOS/cli")
        #expect(command.arguments == ["/tmp/progetto", "/tmp/progetto/src/main.swift:42:7"])
    }

    @Test func xcodeSelectsTheLineWithXed() {
        let command = editor("com.apple.dt.Xcode", at: "/Applications/Xcode.app")
            .command(opening: location, in: worktree) { _ in true }
        #expect(command.executable.path == "/Applications/Xcode.app/Contents/Developer/usr/bin/xed")
        #expect(command.arguments == ["-l", "42", "/tmp/progetto/src/main.swift"])
    }

    @Test func withoutAColumnOnlyTheLineIsPassed() {
        let command = editor("com.microsoft.VSCode", at: "/Applications/Visual Studio Code.app")
            .command(opening: SourceLocation(file: location.file, line: 3), in: worktree) { _ in true }
        #expect(command.arguments.last == "/tmp/progetto/src/main.swift:3")
    }

    @Test func aFileOutsideTheWorktreeOpensWithoutItsFolder() {
        let outside = SourceLocation(file: URL(filePath: "/etc/hosts"), line: 2)
        let command = editor("com.microsoft.VSCode", at: "/Applications/Visual Studio Code.app")
            .command(opening: outside, in: worktree) { _ in true }
        #expect(command.arguments == ["-g", "/etc/hosts:2"])
    }

    @Test func anotherAppOpensWithOpenAndNoLine() {
        let textEdit = editor("com.apple.TextEdit", at: "/System/Applications/TextEdit.app")
        let command = textEdit.command(opening: location, in: worktree) { _ in true }
        #expect(textEdit.kind == .other)
        #expect(textEdit.name == "TextEdit")
        #expect(command.executable.path == "/usr/bin/open")
        #expect(command.arguments == ["-b", "com.apple.TextEdit", "/tmp/progetto/src/main.swift"])
    }

    @Test func aMissingCLIFallsBackToOpenWithoutTheLine() {
        let command = editor("dev.zed.Zed", at: "/Applications/Zed.app")
            .command(opening: location, in: worktree) { _ in false }
        #expect(command.executable.path == "/usr/bin/open")
        #expect(command.arguments == ["-b", "dev.zed.Zed", "/tmp/progetto/src/main.swift"])
    }

    @Test func theFirstKnownEditorFoundIsTheDefault() {
        let installed = ["dev.zed.Zed": "/Applications/Zed.app", "com.apple.dt.Xcode": "/Applications/Xcode.app"]
        let editor = EditorLauncher.preferred(chosen: "") { installed[$0].map { URL(filePath: $0) } }
        #expect(editor?.bundleID == "dev.zed.Zed")
        #expect(editor?.kind == .zed)
    }

    @Test func theChosenEditorWinsWhileInstalled() {
        let installed = ["com.microsoft.VSCode": "/Applications/Visual Studio Code.app",
                         "com.apple.dt.Xcode": "/Applications/Xcode.app"]
        let locate: (String) -> URL? = { installed[$0].map { URL(filePath: $0) } }
        #expect(EditorLauncher.preferred(chosen: "com.apple.dt.Xcode", locate: locate)?.kind == .xcode)
        #expect(EditorLauncher.preferred(chosen: "dev.zed.Zed", locate: locate)?.kind == .visualStudioCode)
    }

    @Test func withoutAnEditorThereIsNoButton() {
        #expect(EditorLauncher.preferred(chosen: "") { _ in nil } == nil)
        #expect(EditorLauncher.preferred(chosen: "com.apple.TextEdit") { _ in nil } == nil)
    }

    @Test func theEditorsCLIGetsOnlyTheBasicsAndTheSystemPath() {
        let environment = ChildEnvironment.makeForEditor(base: ["HOME": "/Users/u", "ANTHROPIC_API_KEY": "x",
                                                                "PATH": "/opt/evil"])
        #expect(environment == ["HOME": "/Users/u", "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"])
    }
}
