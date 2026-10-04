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
        #expect(try await downloader(loginPath: own).installedExecutable() == own)
    }

    @Test func withoutAnyYTDLPThereIsNone() async throws {
        #expect(try await downloader().installedExecutable() == nil)
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

private nonisolated final class Clock: Sendable {
    private let current: Mutex<Date>
    init(date: Date) { current = Mutex(date) }
    var date: Date {
        get { current.withLock { $0 } }
        set { current.withLock { $0 = newValue } }
    }
}
