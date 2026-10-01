import Darwin
import Foundation
import os

/// A shell in a pseudo-terminal of Bubo's own, started through the bundle's launcher with the disclaim (spec 15).
///
/// The launcher makes the terminal the shell's controlling terminal, so ⌃C and job control work; the shell and
/// everything it runs are responsible for themselves and inherit none of Bubo's privacy permissions.
final class PTYSession {
    /// The shell's process identifier, also its session and process group.
    let pid: pid_t
    /// Receives what the shell writes, on the main thread.
    var onOutput: ((ArraySlice<UInt8>) -> Void)?
    /// Called once, on the main thread, when the shell exits.
    var onExit: (() -> Void)?

    /// Bubo's side of the pseudo-terminal.
    private let primary: Int32
    private let channel: DispatchIO
    /// The terminal device, the controlling terminal of everything that runs in it.
    private let device: dev_t

    /// The launcher in Bubo's bundle.
    static let launcher = Bundle.main.bundleURL.appending(path: "Contents/Helpers/bubo-terminal")

    /// The user's login shell, from the user database, else `SHELL`, else zsh.
    static var loginShell: URL {
        if let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell, shell.pointee != 0 {
            return URL(filePath: String(cString: shell))
        }
        return URL(filePath: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh")
    }

    /// Starts `shell` with `arguments` in `folder`, in a new terminal of `columns` by `rows`.
    ///
    /// - Throws: ``ProcessSpawnerError`` when the terminal cannot be opened or the launcher cannot start.
    init(folder: URL, environment: [String: String], shell: URL = loginShell, arguments: [String] = ["-l"],
         columns: Int = 80, rows: Int = 24, launcher: URL = launcher) throws {
        let primary = posix_openpt(O_RDWR | O_NOCTTY | O_CLOEXEC)
        guard primary >= 0 else { throw ProcessSpawnerError.failed(errno: errno) }
        guard grantpt(primary) == 0, unlockpt(primary) == 0, let name = ptsname(primary) else {
            let error = errno
            Darwin.close(primary)
            throw ProcessSpawnerError.failed(errno: error)
        }
        let secondary = open(name, O_RDWR | O_NOCTTY | O_CLOEXEC)
        guard secondary >= 0 else {
            let error = errno
            Darwin.close(primary)
            throw ProcessSpawnerError.failed(errno: error)
        }
        // Bubo keeps only its own side: the shell's goes with the last process that has it open.
        defer { Darwin.close(secondary) }
        var status = stat()
        fstat(secondary, &status)
        var size = winsize(ws_row: UInt16(rows), ws_col: UInt16(columns), ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(primary, TIOCSWINSZ, &size)
        do {
            pid = try ProcessSpawner.spawn(launcher, arguments: [shell.path, shell.lastPathComponent] + arguments,
                                           environment: environment, terminal: secondary, in: folder)
        } catch {
            Darwin.close(primary)
            throw error
        }
        self.primary = primary
        device = status.st_rdev
        channel = DispatchIO(type: .stream, fileDescriptor: primary, queue: .main) { _ in Darwin.close(primary) }
        channel.setLimit(lowWater: 1)
        read()
        let pid = pid
        Task { [weak self] in
            _ = await ProcessSpawner.waitForExit(of: pid)
            self?.didExit()
        }
    }

    /// Sends what the user typed or pasted to the shell.
    func write(_ bytes: ArraySlice<UInt8>) {
        let data = bytes.withUnsafeBytes { DispatchData(bytes: $0) }
        channel.write(offset: 0, data: data, queue: .main) { _, _, _ in }
    }

    /// Tells the shell and what runs in it the terminal's new size.
    func resize(columns: Int, rows: Int) {
        var size = winsize(ws_row: UInt16(rows), ws_col: UInt16(columns), ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(primary, TIOCSWINSZ, &size)
    }

    /// The names of what runs in the terminal besides the shell: the commands and their jobs.
    var runningCommands: [String] {
        Self.processes(on: device).filter { $0 != pid }.compactMap(Self.name(of:))
    }

    /// The processes to stop when the terminal closes: the shell and everything on its terminal.
    var processes: [pid_t] {
        Array(Set(Self.processes(on: device) + [pid]))
    }

    /// Closes the terminal: hangs up on the shell and what runs in it, then kills what ignores the hang-up.
    func close() async {
        let processes = processes
        channel.close(flags: .stop)
        await Self.stop(processes)
    }

    /// Hangs up on `processes`, waits up to `grace` for them to exit, then kills the ones still alive.
    @concurrent
    static func stop(_ processes: [pid_t], grace: Duration = .milliseconds(500)) async {
        hangUp(processes, grace: grace)
    }

    /// ``stop(_:grace:)`` on the calling thread, for when Bubo quits.
    nonisolated static func hangUp(_ processes: [pid_t], grace: Duration = .milliseconds(500)) {
        guard !processes.isEmpty else { return }
        for process in processes {
            kill(process, SIGHUP)
            // A stopped job receives the hang-up only once it continues.
            kill(process, SIGCONT)
        }
        let deadline = ContinuousClock.now + grace
        var alive = processes.filter(isAlive)
        while !alive.isEmpty && ContinuousClock.now < deadline {
            usleep(10_000)
            alive = alive.filter(isAlive)
        }
        guard !alive.isEmpty else { return }
        Logger.terminal.notice("\(alive.count) terminal processes ignored the hang-up: killed")
        for process in alive { kill(process, SIGKILL) }
    }

    private func read() {
        channel.read(offset: 0, length: Int.max, queue: .main) { [weak self] _, data, _ in
            guard let data, !data.isEmpty else { return }
            MainActor.assumeIsolated { self?.onOutput?(ArraySlice(data)) }
        }
    }

    private func didExit() {
        channel.close(flags: .stop)
        onExit?()
        onExit = nil
    }

    /// The processes whose controlling terminal is `device`.
    private nonisolated static func processes(on device: dev_t) -> [pid_t] {
        var pids = [pid_t](repeating: 0, count: 256)
        let bytes = pids.withUnsafeMutableBytes {
            proc_listpids(UInt32(PROC_TTY_ONLY), UInt32(bitPattern: device), $0.baseAddress, Int32($0.count))
        }
        guard bytes > 0 else { return [] }
        return pids.prefix(Int(bytes) / MemoryLayout<pid_t>.size).filter { $0 > 0 && isAlive($0) }
    }

    /// Whether `process` exists and is not a zombie waiting to be reaped.
    nonisolated static func isAlive(_ process: pid_t) -> Bool {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(process, PROC_PIDTBSDINFO, 0, &info, size) == size else { return false }
        return info.pbi_status != UInt32(SZOMB)
    }

    private nonisolated static func name(of process: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 2 * Int(MAXCOMLEN) + 1)
        guard proc_name(process, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}

extension Logger {
    nonisolated static let terminal = Logger(subsystem: "com.mgiuditta.bubo", category: "terminal")
}
