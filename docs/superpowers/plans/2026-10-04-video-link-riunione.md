# Video e link sull'Orb → Riunione Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Un link a un video (trascinato sull'Orb o scritto nel menu «Trascrivi un video da un link…») diventa una Riunione nel Secondo cervello, con `yt-dlp` trovato o scaricato con il permesso dell'utente e verificato con SHA-256.

**Architecture:** Un solo tipo nuovo, `VideoDownloader` (struct `nonisolated`, dipendenze iniettate: login shell, rete, `ProcessRunner`, orologio), trova/installa/aggiorna `yt-dlp` e scarica l'audio in una cartella temporanea. `MeetingImporter` lo usa per un link come per un file importato (titolo = titolo del video, impronta = URL normalizzato, fonte = URL). `OrbDropTarget` classifica il drop (file media / link / altro); l'Orb mostra durante il trascinamento la pillola «Rilascia: trascrivo e salvo nel cervello» (nuovo caso di `PanelStatus`).

**Tech Stack:** Swift 6.2 (isolamento predefinito MainActor), AppKit, SwiftUI, CryptoKit (SHA-256 tramite `MeetingImportFile.fingerprint(of:)`), Foundation `Process` tramite `ProcessRunner`, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-04-casa-cervello-design.md`, sezione 3 (Video e link sull'Orb → Riunione).

## Global Constraints

- Ricerca di `yt-dlp`: prima il PATH di login dell'utente, poi `~/Library/Application Support/Bubo/bin/yt-dlp`.
- Download di `yt-dlp_macos` solo dopo un permesso esplicito, dall'ultima release di `yt-dlp/yt-dlp`; SHA-256 contro `SHA2-256SUMS` della **stessa** release; su mismatch il file si cancella e nulla viene eseguito.
- `-U` al più una volta al giorno, solo sulla copia di Bubo.
- `Process` senza shell, argomenti in un array, URL dopo `--`.
- Annullare termina il processo e cancella la cartella temporanea.
- Impronta = URL normalizzato: schema e host minuscoli, senza frammento, senza parametri `utm_*`, `si`, `feature`.
- Un URL trascinato che yt-dlp non sa scaricare diventa un Allegato come oggi.
- Testi (String Catalog, sorgente italiano, inglese tradotto): «Questo link non ha un video che posso scaricare.», «Non sono riuscito a scaricare yt-dlp», «Rilascia: trascrivo e salvo nel cervello», «Trascrivi un video da un link…».
- Nessuna modifica agli entitlement: Bubo non è in sandbox (`Bubo/Bubo.entitlements` non ha `com.apple.security.app-sandbox`), quindi può eseguire un binario scaricato come processo figlio; il runtime rinforzato vincola solo Bubo, non i figli.
- Deviazione dichiarata dallo spec: niente `-x`, che richiede ffmpeg/ffprobe (assenti su un Mac comune); al suo posto `-f bestaudio[ext=m4a]/bestaudio`, che su YouTube dà un m4a leggibile da AVFoundation. Un formato non leggibile vale come «nessun video».

---

### Task 1: VideoDownloader — funzioni pure (impronta, SHA2-256SUMS, argomenti)

**Files:**
- Create: `Bubo/Meetings/VideoDownloader.swift`
- Modify: `Bubo/Meetings/MeetingFailure.swift` (casi `noVideo`, `downloaderUnavailable`)
- Test: `BuboTests/VideoDownloaderTests.swift`

**Interfaces:**
- Produces: `VideoDownloader.fingerprint(of: URL) -> String`, `VideoDownloader.checksum(of: String, in: String) -> String?`, `VideoDownloader.arguments(downloading: URL, into: URL) -> [String]`, `MeetingFailure.noVideo`, `MeetingFailure.downloaderUnavailable`.

- [ ] **Step 1: Write the failing tests**

```swift
import CryptoKit
import Foundation
import Synchronization
import Testing
@testable import Bubo

struct VideoDownloaderTests {
    @Test(arguments: [
        ("HTTPS://WWW.YouTube.com/watch?v=abc&utm_source=x&si=1&feature=share#t=10", "https://www.youtube.com/watch?v=abc"),
        ("https://youtu.be/abc?si=XyZ", "https://youtu.be/abc"),
        ("https://vimeo.com/123?UTM_medium=mail&h=9f", "https://vimeo.com/123?h=9f"),
        ("https://example.com/Path/Video", "https://example.com/Path/Video"),
    ])
    func theFingerprintIsTheNormalizedLink(link: String, fingerprint: String) throws {
        #expect(VideoDownloader.fingerprint(of: try #require(URL(string: link))) == fingerprint)
    }

    static let hash = String(repeating: "ab", count: 32)
    static let sums = """
        \(String(repeating: "0", count: 64))  yt-dlp
        \(String(repeating: "1", count: 64))  yt-dlp_macos.zip
        \(hash.uppercased()) *yt-dlp_macos
        \(String(repeating: "2", count: 64))  yt-dlp_macos_legacy
        """

    @Test func theChecksumIsReadForTheExactName() {
        #expect(VideoDownloader.checksum(of: "yt-dlp_macos", in: Self.sums) == Self.hash)
    }

    @Test func aNameNotListedHasNoChecksum() {
        #expect(VideoDownloader.checksum(of: "yt-dlp_linux", in: Self.sums) == nil)
        #expect(VideoDownloader.checksum(of: "yt-dlp_macos", in: "nothex  yt-dlp_macos") == nil)
    }

    @Test func theLinkComesLastAfterTheEndOfOptions() throws {
        let link = try #require(URL(string: "https://www.youtube.com/watch?v=-abc"))
        let folder = URL(filePath: "/tmp/video", directoryHint: .isDirectory)
        let arguments = VideoDownloader.arguments(downloading: link, into: folder)
        #expect(arguments.suffix(2) == ["--", link.absoluteString])
        #expect(arguments.contains("--no-playlist"))
        #expect(arguments.contains("--print-json"))
        let output = try #require(arguments.firstIndex(of: "-o"))
        #expect(arguments[output + 1] == "/tmp/video/%(id)s.%(ext)s")
    }
}
```

- [ ] **Step 2: Run to verify they fail** — `xcodebuild … test -only-testing:BuboTests/VideoDownloaderTests`: build error, `VideoDownloader` not found.

- [ ] **Step 3: Implement**

`MeetingFailure`: add

```swift
    /// The web link has no video that `yt-dlp` can download.
    case noVideo
    /// `yt-dlp` could not be downloaded, or its checksum did not match: nothing was run.
    case downloaderUnavailable
```

and in `explanation`:

```swift
        case .noVideo:
            "Questo link non ha un video che posso scaricare."
        case .downloaderUnavailable:
            "Non sono riuscito a scaricare yt-dlp"
```

`VideoDownloader.swift` (pure part):

```swift
nonisolated struct VideoDownloader: Sendable {
    static func fingerprint(of link: URL) -> String {
        guard var components = URLComponents(url: link, resolvingAgainstBaseURL: false) else { return link.absoluteString }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        components.fragment = nil
        let kept = components.percentEncodedQueryItems?.filter { item in
            let name = item.name.lowercased()
            return !name.hasPrefix("utm_") && name != "si" && name != "feature"
        }
        components.percentEncodedQueryItems = kept?.isEmpty == false ? kept : nil
        return components.string ?? link.absoluteString
    }

    static func checksum(of name: String, in sums: String) -> String? {
        for line in sums.split(whereSeparator: \.isNewline) {
            let parts = line.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            guard parts.count == 2 else { continue }
            var file = parts[1].trimmingCharacters(in: .whitespaces)
            if file.hasPrefix("*") { file.removeFirst() }
            let hash = parts[0].lowercased()
            if file == name, hash.count == 64, hash.allSatisfy(\.isHexDigit) { return hash }
        }
        return nil
    }

    static func arguments(downloading link: URL, into folder: URL) -> [String] {
        var path = folder.standardizedFileURL.path(percentEncoded: false)
        if path.hasSuffix("/") { path.removeLast() }
        return ["-f", "bestaudio[ext=m4a]/bestaudio", "--no-playlist", "--print-json",
                "-o", path + "/%(id)s.%(ext)s", "--", link.absoluteString]
    }
}
```

- [ ] **Step 4: Run the tests** — PASS.
- [ ] **Step 5: Commit** — `Video da link: impronta, SHA2-256SUMS e argomenti di yt-dlp (#690)`.

### Task 2: VideoDownloader — trovare, installare, aggiornare, scaricare

**Files:**
- Modify: `Bubo/Meetings/VideoDownloader.swift`
- Test: `BuboTests/VideoDownloaderTests.swift`

**Interfaces:**
- Consumes: Task 1.
- Produces:
  - `VideoDownloader.init(binaryFolder:temporaryFolder:loginPathExecutable:fetch:runner:now:)` (all defaulted).
  - `struct VideoDownloader.Video { var audio: URL; var title: String; var folder: URL { get } }`
  - `func installedExecutable() async -> URL?`
  - `func install() async throws(MeetingFailure) -> URL`
  - `func updateIfDue(_ executable: URL) async`
  - `func download(_ link: URL, with executable: URL) async throws(MeetingFailure) -> Video`
  - `var bundledExecutable: URL`

- [ ] **Step 1: Write the failing tests** (a `fake yt-dlp` script in the test's temp folder)

```swift
@Suite(.timeLimit(.minutes(1)))
struct VideoDownloaderProcessTests {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "VideoDownloaderTests-\(UUID().uuidString)",
                                                                directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private var temporaryFolder: URL { root.appending(path: "tmp", directoryHint: .isDirectory) }

    private func downloader(runner: ProcessRunner = .live(environment: ["PATH": "/usr/bin:/bin"]),
                            loginPath: URL? = nil, fetch: @escaping @Sendable (URL) async throws -> Data = { _ in
                                throw URLError(.notConnectedToInternet) },
                            now: @escaping @Sendable () -> Date = { .now }) throws -> VideoDownloader {
        try FileManager.default.createDirectory(at: temporaryFolder, withIntermediateDirectories: true)
        return VideoDownloader(binaryFolder: root.appending(path: "bin", directoryHint: .isDirectory),
                               temporaryFolder: temporaryFolder, loginPathExecutable: { loginPath },
                               fetch: fetch, runner: runner, now: now)
    }

    /// A `yt-dlp` that checks the `--` before the link, writes an m4a where `-o` says and prints its JSON.
    private func fakeYTDLP(_ body: String) throws -> URL {
        let script = root.appending(path: "yt-dlp")
        try "#!/bin/sh\n\(body)\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }

    static let working = """
        out=""; previous=""; link=""
        for argument in "$@"; do
          [ "$previous" = "-o" ] && out="$argument"
          [ "$previous" = "--" ] && link="$argument"
          previous="$argument"
        done
        [ -n "$link" ] || { echo "ERROR: no -- before the link" >&2; exit 2; }
        file=$(echo "$out" | sed 's/%(id)s/abc123/; s/%(ext)s/m4a/')
        printf 'audio' > "$file"
        echo '{"id": "abc123", "title": "Lezione di prova", "webpage_url": "'"$link"'"}'
        """

    @Test func theFakeVideoBecomesAnAudioFileWithItsTitle() async throws {
        let video = try await downloader().download(try #require(URL(string: "https://youtu.be/abc123")),
                                                    with: try fakeYTDLP(Self.working))
        #expect(video.title == "Lezione di prova")
        #expect(video.audio.lastPathComponent == "abc123.m4a")
        #expect(try String(contentsOf: video.audio, encoding: .utf8) == "audio")
    }

    @Test func aLinkWithoutVideoFailsAndLeavesNothing() async throws {
        let script = try fakeYTDLP("echo 'ERROR: Unsupported URL: https://example.com' >&2; exit 1")
        await #expect(throws: MeetingFailure.noVideo) {
            _ = try await downloader().download(try #require(URL(string: "https://example.com")), with: script)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: temporaryFolder.path).isEmpty)
    }

    @Test func cancellingTerminatesTheProcessAndRemovesTheTemporaryFolder() async throws {
        let started = root.appending(path: "started")
        let script = try fakeYTDLP("touch '\(started.path)'; sleep 30")
        let downloader = try downloader()
        let link = try #require(URL(string: "https://youtu.be/abc123"))
        let download = Task { try await downloader.download(link, with: script) }
        while !FileManager.default.fileExists(atPath: started.path) { try await Task.sleep(for: .milliseconds(20)) }
        download.cancel()
        await #expect(throws: MeetingFailure.noVideo) { _ = try await download.value }
        #expect(try FileManager.default.contentsOfDirectory(atPath: temporaryFolder.path).isEmpty)
    }

    @Test func theUsersOwnYTDLPComesFirst() async throws {
        let own = URL(filePath: "/opt/homebrew/bin/yt-dlp")
        #expect(await downloader(loginPath: own).installedExecutable() == own)
    }

    @Test func withoutAnyYTDLPThereIsNone() async throws {
        #expect(await downloader().installedExecutable() == nil)
    }

    /// The network of a release whose `SHA2-256SUMS` lists `listedHash` for the binary `binary`.
    private func release(binary: Data, listedHash: String) -> @Sendable (URL) async throws -> Data {
        { url in
            switch url.absoluteString {
            case VideoDownloader.latestRelease.absoluteString:
                Data("""
                    {"tag_name": "2026.09.30", "assets": [
                      {"name": "SHA2-256SUMS", "browser_download_url": "https://github.com/yt-dlp/yt-dlp/releases/download/2026.09.30/SHA2-256SUMS"},
                      {"name": "yt-dlp_macos", "browser_download_url": "https://github.com/yt-dlp/yt-dlp/releases/download/2026.09.30/yt-dlp_macos"}
                    ]}
                    """.utf8)
            case let address where address.hasSuffix("/SHA2-256SUMS"): Data("\(listedHash)  yt-dlp_macos\n".utf8)
            case let address where address.hasSuffix("/yt-dlp_macos"): binary
            default: throw URLError(.fileDoesNotExist)
            }
        }
    }

    @Test func aBinaryWhoseChecksumMatchesIsInstalledExecutable() async throws {
        let binary = Data("#!/bin/sh\necho ok\n".utf8)
        let hash = SHA256.hash(data: binary).map { String(format: "%02x", $0) }.joined()
        let downloader = try downloader(fetch: release(binary: binary, listedHash: hash))
        let installed = try await downloader.install()
        #expect(installed == downloader.bundledExecutable)
        #expect(FileManager.default.isExecutableFile(atPath: installed.path))
        #expect(await downloader.installedExecutable() == installed)
    }

    @Test func aBinaryWhoseChecksumDiffersIsDeleted() async throws {
        let downloader = try downloader(fetch: release(binary: Data("evil".utf8),
                                                       listedHash: String(repeating: "0", count: 64)))
        await #expect(throws: MeetingFailure.downloaderUnavailable) { _ = try await downloader.install() }
        let left = (try? FileManager.default.contentsOfDirectory(atPath: downloader.binaryFolder.path)) ?? []
        #expect(!left.contains { $0.hasPrefix("yt-dlp") && $0 != "yt-dlp.updated" })
    }

    @Test func withoutNetworkNothingIsInstalled() async throws {
        await #expect(throws: MeetingFailure.downloaderUnavailable) { _ = try await downloader().install() }
    }

    @Test func bubosCopyUpdatesAtMostOnceADay() async throws {
        let calls = Calls()
        let clock = Clock(date: .now)
        let runner = ProcessRunner { executable, arguments in
            await calls.append(arguments)
            return ProcessOutput(exitCode: 0, standardOutput: "")
        }
        let downloader = try downloader(runner: runner, now: { clock.date })
        await downloader.updateIfDue(downloader.bundledExecutable)
        await downloader.updateIfDue(downloader.bundledExecutable)
        clock.date += 25 * 60 * 60
        await downloader.updateIfDue(downloader.bundledExecutable)
        await downloader.updateIfDue(URL(filePath: "/opt/homebrew/bin/yt-dlp"))
        #expect(await calls.all == [["-U"], ["-U"]])
    }
}

private actor Calls {
    private(set) var all: [[String]] = []
    func append(_ arguments: [String]) { all.append(arguments) }
}

private final class Clock: Sendable {
    private let current: Mutex<Date>
    init(date: Date) { current = Mutex(date) }
    var date: Date {
        get { current.withLock { $0 } }
        set { current.withLock { $0 = newValue } }
    }
}
```

- [ ] **Step 2: Run** — compile errors for the missing API.

- [ ] **Step 3: Implement** — see `Bubo/Meetings/VideoDownloader.swift` in the commit: properties with live defaults (`URL.applicationSupportDirectory/Bubo/bin`, `FileManager.default.temporaryDirectory`, login shell `-l -i -c "command -v yt-dlp"` with a 5 s timeout through `ProcessRunner.disclaimed`, `URLSession.shared.data(from:)` requiring HTTP 200, `ProcessRunner.live(environment:)` with the user's basics and `/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin`). `install()` reads `releases/latest` from the GitHub API, takes `yt-dlp_macos` and `SHA2-256SUMS` from the same release (HTTPS only), writes `yt-dlp.download`, compares `MeetingImportFile.fingerprint(of:)` with the listed hash, deletes on mismatch, `chmod 755`, moves to `yt-dlp`, touches `yt-dlp.updated`. `updateIfDue` compares the marker's modification date with `now()` and runs `-U` (timeout 2 min) only for `bundledExecutable`. `download` creates `temporaryFolder/Bubo-video-<UUID>`, runs `arguments(downloading:into:)`, requires exit 0 and a file whose `MeetingImportFile.kind` is `.audio` or `.video`, reads `title` from the first JSON line; every failure (cancellation included: `ProcessRunner` kills the child on cancel) removes the folder and throws `.noVideo`. `install` and `download` are `@concurrent` (hashing tens of MB never on the main actor).

- [ ] **Step 4: Run the tests** — PASS.
- [ ] **Step 5: Commit** — `Video da link: VideoDownloader trova, verifica e usa yt-dlp (#690)`.

### Task 3: Riunione da un link (MeetingImporter, MeetingNote, menu)

**Files:**
- Modify: `Bubo/Meetings/MeetingNote.swift` (`Source.link`), `Bubo/Meetings/MeetingImporter.swift`, `Bubo/Meetings/MeetingMenuItems.swift`
- Test: `BuboTests/MeetingNoteTests.swift`

**Interfaces:**
- Consumes: `VideoDownloader` (Task 2).
- Produces: `MeetingNote.Source(fileName:fingerprint:link:)`; `MeetingImporter.start(importingVideoAt link: URL, onNoVideo: (() -> Void)? = nil)`; `MeetingImporter.chooseVideoLink()`.

- [ ] **Step 1: Failing test** in `MeetingNoteTests`:

```swift
    @Test func aRiunioneFromALinkSaysTheLinkInsteadOfTheFile() throws {
        var note = MeetingNote(title: "Lezione", start: .now, duration: nil, app: nil, transcript: [])
        let link = try #require(URL(string: "https://www.youtube.com/watch?v=abc"))
        note.source = MeetingNote.Source(fileName: "Lezione", fingerprint: "https://www.youtube.com/watch?v=abc", link: link)
        let markdown = note.markdown(in: .gmt)
        #expect(markdown.contains("link: \"https://www.youtube.com/watch?v=abc\""))
        #expect(markdown.contains("impronta: https://www.youtube.com/watch?v=abc"))
        #expect(!markdown.contains("file: "))
    }
```

- [ ] **Step 2: Run** — fails (no `link:` parameter).
- [ ] **Step 3: Implement**
  - `Source` gains `var link: URL? = nil`; `markdown` writes `link: "<url>"` instead of `file:` when set.
  - `MeetingImporter` gains `videoDownloader` (init parameter, default `VideoDownloader()`), `start(importingVideoAt:onNoVideo:)`, `importVideo(at:onNoVideo:)`: no Secondo cervello → failure; impronta already known → `duplicates = 1`; `installedExecutable()` or, after the consent alert («Scarico yt-dlp per trascrivere il video?», buttons «Scarica e trascrivi» / «Annulla»), `install()`; `updateIfDue`; `download`; then `showWindow()`, the same `note(of:)` as a file, title = video title, start = now, `Source(fileName: title, fingerprint: impronta, link: link)`, summary, write, temp folder removed. `.noVideo` or a declined consent with `onNoVideo` set → `onNoVideo()` and no outcome (the drop's Allegato); without it the window shows the failure.
  - `chooseVideoLink()`: `NSAlert` with a text field (label «Link del video», prefilled from the clipboard when it holds an http(s) link), buttons «Trascrivi» / «Annulla».
  - `MeetingMenuItems`: `Button("Trascrivi un video da un link…") { recorder.imports.chooseVideoLink() }.disabled(recorder.imports.isImporting)`.
- [ ] **Step 4: Run** — PASS.
- [ ] **Step 5: Commit** — `Video da link: la Riunione nasce dal link, menu «Trascrivi un video da un link…» (#690)`.

### Task 4: Drop sull'Orb e pillola «Rilascia: trascrivo e salvo nel cervello»

**Files:**
- Modify: `Bubo/Panel/OrbDropTarget.swift`, `Bubo/Panel/OrbPanelView.swift`, `Bubo/Panel/OrbPanelController.swift`, `Bubo/Panel/PanelStatus.swift`, `Bubo/Panel/PanelStatusLayout.swift`, `Bubo/App/AppDelegate.swift`
- Test: `BuboTests/OrbDropTargetTests.swift` (new), `BuboTests/PanelStatusTests.swift`

**Interfaces:**
- Produces: `OrbDropTarget.Drop` (`.meetingFiles([URL])`, `.videoLink(URL)`, `.attachments`, `isTranscription`), `OrbDropTarget.drop(files:links:)`, `OrbDropTarget.drop(in:)`, `PanelStatus.dropHint`, `PanelZone.hintSide`, `PanelStatusLayout.frame(ofSize:besidePanel:on:visibleFrame:)`, `OrbPanelController.importVideo: (URL, @escaping () -> Void) -> Void`.

- [ ] **Step 1: Failing tests**

```swift
@MainActor
struct OrbDropTargetTests {
    @Test func mediaFilesAreRiunioni() {
        let files = [URL(filePath: "/tmp/a.m4a"), URL(filePath: "/tmp/b.mp4")]
        #expect(OrbDropTarget.drop(files: files, links: []) == .meetingFiles(files))
        #expect(OrbDropTarget.drop(files: files, links: []).isTranscription)
    }

    @Test func aWebLinkAloneIsAVideoLink() throws {
        let link = try #require(URL(string: "https://www.youtube.com/watch?v=abc"))
        #expect(OrbDropTarget.drop(files: [], links: [link]) == .videoLink(link))
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
```

`PanelStatusTests`:

```swift
    @Test func theDropHintSaysWhatADropDoes() {
        #expect(PanelStatus.dropHint.text == "Rilascia: trascrivo e salvo nel cervello")
        #expect(!PanelStatus.dropHint.showsLume)
    }

    @Test(arguments: [(PanelZone.topLeft, PanelBubbleSide.below), (.center, .below), (.bottom, .above),
                      (.bottomRight, .above)])
    func theDropHintSitsUnderTheOrbUnlessThereIsNoRoom(zone: PanelZone, side: PanelBubbleSide) {
        #expect(zone.hintSide == side)
    }
```

- [ ] **Step 2: Run** — compile errors.
- [ ] **Step 3: Implement**
  - `OrbDropTarget.Drop` + classifiers (web = `http`/`https`, one link, no file).
  - `OrbPanelView.onDropEnter: (NSPasteboard) -> Void`, `draggingEnded` calls `onDropExit`.
  - Controller: `isOfferingTranscription` drives `updateStatus()` (`.dropHint` wins over every other pill, at any size); `placeStatus` uses `zone.hintSide` for the hint; `drop(_:into:)` switches on `OrbDropTarget.drop(in:)`: `.meetingFiles` → `importMeetings`, `.videoLink` → computes today's Allegati first (an image dragged with its link is saved now) and calls `importVideo(link) { attach(fallback) }`, `.attachments` → today's code.
  - `PanelStatus.dropHint`: text «Rilascia: trascrivo e salvo nel cervello», help «Bubo trascrive l'audio e salva la Riunione nel Secondo cervello», press does nothing.
  - `AppDelegate`: `panel.importVideo = { [meetings] link, fallback in meetings.imports.start(importingVideoAt: link, onNoVideo: fallback) }`.
- [ ] **Step 4: Run** — PASS.
- [ ] **Step 5: String Catalog** — `xcrun xcstringstool sync` with the Debug build's `.stringsdata`, then English for every new key; `scripts/polish-check.sh` passes.
- [ ] **Step 6: Commit** — `Video da link: drop sull'Orb e «Rilascia: trascrivo e salvo nel cervello» (#690)`.

### Task 5: Verifica e consegna

- [ ] `xcodegen generate`, Debug build, `-only-testing` on `VideoDownloaderTests`, `VideoDownloaderProcessTests`, `OrbDropTargetTests`, `PanelStatusTests`, `MeetingNoteTests`, `MeetingImportTests`, `MenuBarContentTests`; then `scripts/polish-check.sh`.
- [ ] Push `feat/video-link-riunione`, PR to `main` referencing #690, issue `ready-for-human` «Video da link: prova con un link YouTube vero che diventa una Riunione».

## Self-review

- Spec §3 «File»: drag hint → Task 4. «Link»: ingressi → Tasks 3–4; steps 1–4 of `VideoDownloader` → Tasks 1–2; impronta/titolo/fonte → Tasks 1, 3; fallback Allegato → Task 4. «Errori» → Tasks 1–2 (cancel test). «Note legali»: download only on explicit action (drop or menu, consent alert), only temporary audio, removed after the note. «Test» → Tasks 1, 2, 4; manual test → Task 5 issue.
- Deviation: no `-x` (ffmpeg); see Global Constraints.
