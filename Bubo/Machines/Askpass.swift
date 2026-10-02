import Foundation

/// Bubo's `SSH_ASKPASS` for one connection: OpenSSH's questions, a new host key or a passphrase, reach Bubo's
/// sheets, and the answers go back through a FIFO, never through a file.
///
/// The helper is a small shell script in a private folder: it writes the question to `<pid>.question`, then reads
/// the answer from the FIFO `<pid>.answer`, which Bubo opens only to write it. Bubo keeps no answer.
nonisolated struct Askpass: Sendable {
    /// The variable that tells the helper its folder.
    static let folderVariable = "BUBO_ASKPASS_FOLDER"

    /// The private folder of the connection, readable only by the user.
    let folder: URL

    /// The helper `SSH_ASKPASS` points to.
    var script: URL { folder.appending(path: "askpass") }

    /// The helper's text. The answer starts with `y`, followed by what to print, or is `n` to refuse.
    static let scriptText = """
        #!/bin/sh
        folder="$\(folderVariable)"
        [ -d "$folder" ] || exit 1
        answer="$folder/$$.answer"
        mkfifo -m 600 "$answer" || exit 1
        printf '%s' "$1" > "$folder/$$.tmp" && mv "$folder/$$.tmp" "$folder/$$.question"
        reply=$(cat "$answer")
        rm -f "$answer"
        case "$reply" in
            y*) printf '%s\\n' "${reply#y}" ;;
            *) exit 1 ;;
        esac

        """

    /// Creates the private folder and its helper under `parent`.
    static func make(in parent: URL = .temporaryDirectory) throws -> Askpass {
        let folder = parent.appending(path: "bubo-askpass-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let askpass = Askpass(folder: folder)
        try Data(scriptText.utf8).write(to: askpass.script)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: askpass.script.path)
        return askpass
    }

    /// Deletes the folder, the helper and any question left.
    func remove() {
        try? FileManager.default.removeItem(at: folder)
    }

    /// The questions waiting, by helper: each is read once and deleted.
    func takeQuestions() -> [(id: String, text: String)] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { $0.hasSuffix(".question") }.sorted().compactMap { name in
            let file = folder.appending(path: name)
            defer { try? FileManager.default.removeItem(at: file) }
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
            return (String(name.dropLast(".question".count)), text)
        }
    }

    /// Gives the helper `id` its answer: `nil` refuses, so OpenSSH gives up.
    ///
    /// Waits up to two seconds for the helper to open its FIFO; the answer is written to the pipe only.
    func answer(_ id: String, with text: String?) async {
        let path = folder.appending(path: "\(id).answer").path
        let reply = Data(((text.map { "y" + $0 }) ?? "n").utf8)
        for _ in 0..<40 {
            // Non-blocking, so that a helper already gone cannot hold Bubo: ENXIO until it opens the FIFO to read.
            let descriptor = open(path, O_WRONLY | O_NONBLOCK)
            if descriptor >= 0 {
                let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
                try? handle.write(contentsOf: reply)
                try? handle.close()
                return
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }
}
