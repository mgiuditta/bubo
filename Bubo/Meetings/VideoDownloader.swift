import Foundation

/// Downloads the audio of a web video with `yt-dlp`, so a link can become a Riunione.
///
/// Uses the user's own `yt-dlp` when there is one, else Bubo's copy in Application Support, which it installs only
/// when asked, from the latest GitHub release and checked against that release's `SHA2-256SUMS`, and updates at most
/// once a day. Never runs a shell: arguments go in an array, the link after `--`.
nonisolated struct VideoDownloader: Sendable {
    /// A downloaded video: its audio, in a temporary folder of its own, and its title.
    struct Video: Equatable, Sendable {
        /// The audio file.
        var audio: URL
        /// The video's title, as the site gives it.
        var title: String
        /// The temporary folder that holds `audio`; the caller removes it once the Riunione is saved.
        var folder: URL { audio.deletingLastPathComponent() }
    }

    /// The GitHub API address of the latest `yt-dlp` release.
    static let latestRelease = URL(string: "https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest")!
    /// The name of the macOS binary in a release, and in `SHA2-256SUMS`.
    static let binaryName = "yt-dlp_macos"

    /// Where Bubo keeps its own copy of `yt-dlp`.
    var binaryFolder: URL
    /// Where downloads go, each in a folder of its own.
    var temporaryFolder: URL
    /// The user's own `yt-dlp`, if any.
    var loginPathExecutable: @Sendable () async -> URL?
    /// Reads an address from the network; only `https` addresses are ever passed.
    var fetch: @Sendable (URL) async throws -> Data
    /// Runs `yt-dlp`, disclaimed (ADR 0005): a downloaded program never inherits Bubo's microphone, screen or
    /// Files and Folders permissions.
    var runner: ProcessRunner
    /// The current time, for the daily update.
    var now: @Sendable () -> Date

    /// Creates a downloader; the defaults are the real folders, shell, network and processes.
    init(binaryFolder: URL = .applicationSupportDirectory.appending(path: "Bubo/bin", directoryHint: .isDirectory),
         temporaryFolder: URL = FileManager.default.temporaryDirectory,
         loginPathExecutable: @escaping @Sendable () async -> URL? = VideoDownloader.userExecutable,
         fetch: @escaping @Sendable (URL) async throws -> Data = VideoDownloader.fetchOverHTTPS,
         runner: ProcessRunner = .disclaimed(environment: VideoDownloader.environment),
         now: @escaping @Sendable () -> Date = { .now }) {
        self.binaryFolder = binaryFolder
        self.temporaryFolder = temporaryFolder
        self.loginPathExecutable = loginPathExecutable
        self.fetch = fetch
        self.runner = runner
        self.now = now
    }

    /// Bubo's own copy of `yt-dlp`.
    var bundledExecutable: URL { binaryFolder.appending(path: "yt-dlp") }
    /// The file whose modification date says when Bubo's copy was last updated.
    private var updateMarker: URL { binaryFolder.appending(path: "yt-dlp.updated") }

    // MARK: - Pure parts

    /// The impronta of a Riunione made from `link`: the link with lowercase scheme and host, without fragment and
    /// without the tracking parameters `utm_*`, `si` and `feature`.
    static func fingerprint(of link: URL) -> String {
        guard var components = URLComponents(url: link, resolvingAgainstBaseURL: false) else {
            return link.absoluteString
        }
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

    /// The lowercase SHA-256 listed for the file `name` in a `SHA2-256SUMS` text; `nil` when it is not listed or the
    /// hash is malformed.
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

    /// The arguments that download the audio of `link` into `folder` and print its metadata as JSON.
    ///
    /// No `-x`: it needs ffmpeg, which a Mac usually lacks; m4a first, which AVFoundation reads.
    static func arguments(downloading link: URL, into folder: URL) -> [String] {
        var path = folder.standardizedFileURL.path(percentEncoded: false)
        if path.hasSuffix("/") { path.removeLast() }
        return ["-f", "bestaudio[ext=m4a]/bestaudio", "--no-playlist", "--print-json",
                "-o", path + "/%(id)s.%(ext)s", "--", link.absoluteString]
    }

    // MARK: - Finding, installing, updating

    /// The `yt-dlp` to use: the user's own first, then Bubo's copy; `nil` when there is none.
    func installedExecutable() async -> URL? {
        if let own = await loginPathExecutable() { return own }
        return FileManager.default.isExecutableFile(atPath: bundledExecutable.path) ? bundledExecutable : nil
    }

    /// Downloads `yt-dlp_macos` from the latest release into Bubo's folder, only if its SHA-256 matches the
    /// release's `SHA2-256SUMS`; on a mismatch the file is deleted and never run.
    ///
    /// - Returns: Bubo's copy, executable.
    /// - Throws: `MeetingFailure.downloaderUnavailable` on any network, checksum or file system failure.
    @concurrent
    func install() async throws(MeetingFailure) -> URL {
        let download = binaryFolder.appending(path: "yt-dlp.download")
        do {
            let release = try JSONDecoder().decode(Release.self, from: try await fetch(Self.latestRelease))
            guard let binary = release.asset(named: Self.binaryName), let sums = release.asset(named: "SHA2-256SUMS")
            else { throw MeetingFailure.downloaderUnavailable }
            let listed = Self.checksum(of: Self.binaryName, in: String(decoding: try await fetch(sums), as: UTF8.self))
            guard let listed else { throw MeetingFailure.downloaderUnavailable }

            try FileManager.default.createDirectory(at: binaryFolder, withIntermediateDirectories: true)
            try await fetch(binary).write(to: download, options: .atomic)
            guard try MeetingImportFile.fingerprint(of: download) == listed else {
                throw MeetingFailure.downloaderUnavailable
            }
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: download.path)
            _ = try? FileManager.default.removeItem(at: bundledExecutable)
            try FileManager.default.moveItem(at: download, to: bundledExecutable)
            markUpdated()
            return bundledExecutable
        } catch {
            try? FileManager.default.removeItem(at: download)
            throw .downloaderUnavailable
        }
    }

    /// Updates Bubo's copy with `-U` when `executable` is that copy and it was not updated in the last day; the
    /// user's own `yt-dlp` is theirs to update. A failed update keeps the copy that is there.
    func updateIfDue(_ executable: URL) async {
        guard executable == bundledExecutable else { return }
        let updated = (try? updateMarker.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate
        if let updated, now().timeIntervalSince(updated) < 24 * 60 * 60 { return }
        markUpdated()
        _ = await runner.run(executable, ["-U"], timeout: .seconds(120))
    }

    /// Records now as the time of the last update.
    private func markUpdated() {
        try? FileManager.default.createDirectory(at: binaryFolder, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: updateMarker.path) {
            FileManager.default.createFile(atPath: updateMarker.path, contents: nil)
        }
        try? FileManager.default.setAttributes([.modificationDate: now()], ofItemAtPath: updateMarker.path)
    }

    // MARK: - Downloading

    /// Downloads the audio of `link` with `executable` into a new temporary folder.
    ///
    /// Cancelling the task terminates `yt-dlp`.
    /// - Throws: `MeetingFailure.noVideo` when `yt-dlp` fails, is cancelled, or gives no audio the Mac can read;
    ///   the temporary folder is then removed.
    @concurrent
    func download(_ link: URL, with executable: URL) async throws(MeetingFailure) -> Video {
        let folder = temporaryFolder.appending(path: "Bubo-video-\(UUID().uuidString)", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let output = try await runner.run(executable, Self.arguments(downloading: link, into: folder))
            try Task.checkCancellation()
            guard output.exitCode == 0 else { throw MeetingFailure.noVideo }
            let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            guard let audio = files.first(where: { [.audio, .video].contains(MeetingImportFile.kind(of: $0)) }) else {
                throw MeetingFailure.noVideo
            }
            let metadata = output.standardOutput.split(whereSeparator: \.isNewline).first
                .flatMap { try? JSONDecoder().decode(Metadata.self, from: Data($0.utf8)) }
            return Video(audio: audio, title: metadata?.title ?? link.host() ?? link.absoluteString)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw .noVideo
        }
    }

    // MARK: - Live dependencies

    /// What `yt-dlp` sees of the environment: the user's basics and the usual folders of Homebrew and the system.
    static var environment: [String: String] {
        var environment = ProcessInfo.processInfo.environment.filter { ChildEnvironment.copied.contains($0.key) }
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        return environment
    }

    /// The user's own `yt-dlp`: Homebrew's first, else what an interactive login shell finds, as Terminal would.
    @Sendable
    static func userExecutable() async -> URL? {
        let candidates = ["/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp"].map { URL(filePath: $0) }
        if let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) {
            return found
        }
        let runner = ProcessRunner.disclaimed(
            environment: ProcessInfo.processInfo.environment.filter { ChildEnvironment.copied.contains($0.key) }
        )
        let shell = URL(filePath: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh")
        guard let output = await runner.run(shell, ["-l", "-i", "-c", "command -v yt-dlp"], timeout: .seconds(5)),
              output.exitCode == 0,
              let path = output.standardOutput.split(whereSeparator: \.isNewline).last,
              path.hasPrefix("/")
        else { return nil }
        return URL(filePath: String(path))
    }

    /// Reads `url` over HTTPS, requiring a 200 answer.
    @Sendable
    static func fetchOverHTTPS(_ url: URL) async throws -> Data {
        guard url.scheme == "https" else { throw URLError(.unsupportedURL) }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }

    /// The part of a GitHub release Bubo reads.
    private struct Release: Decodable {
        struct Asset: Decodable {
            var name: String
            var browserDownloadURL: URL

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
            }
        }

        var assets: [Asset]

        /// The HTTPS address of the asset called `name`.
        func asset(named name: String) -> URL? {
            assets.first { $0.name == name && $0.browserDownloadURL.scheme == "https" }?.browserDownloadURL
        }
    }

    /// The part of `yt-dlp`'s JSON Bubo reads.
    private struct Metadata: Decodable {
        var title: String?
    }
}
