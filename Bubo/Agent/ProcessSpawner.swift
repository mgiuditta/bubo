import Darwin
import Foundation
import os

/// A child process started by ``ProcessSpawner``, with pipes to its standard input and output.
nonisolated struct SpawnedProcess {
    /// The child's process identifier.
    let pid: pid_t
    /// Writes to the child's standard input; closing it tells the child to finish.
    let input: FileHandle
    /// Reads the child's standard output.
    let output: FileHandle
    /// Whether the child is responsible for itself, so it inherits none of Bubo's privacy permissions.
    let isDisclaimed: Bool
}

/// Errors from starting a child process.
nonisolated enum ProcessSpawnerError: Error, Equatable {
    /// `posix_spawn` or one of its setup calls failed with this `errno`.
    case failed(errno: Int32)
}

/// Starts processes with `posix_spawn` and the responsibility disclaim of ADR 0005.
///
/// A disclaimed child is responsible for itself: it does not inherit Bubo's Microphone or
/// other privacy permissions, and asks for Files and Folders in its own name.
nonisolated enum ProcessSpawner {
    /// Starts `executable` with `arguments` and exactly `environment`, standard error inherited or, when
    /// `mergingErrors`, in the same pipe as standard output, in `folder` when given, otherwise in Bubo's own.
    ///
    /// - Throws: ``ProcessSpawnerError`` if the process cannot start.
    static func spawn(_ executable: URL, arguments: [String] = [], environment: [String: String],
                      in folder: URL? = nil, mergingErrors: Bool = false) throws -> SpawnedProcess {
        var input: [Int32] = [0, 0]
        var output: [Int32] = [0, 0]
        guard pipe(&input) == 0 else { throw ProcessSpawnerError.failed(errno: errno) }
        guard pipe(&output) == 0 else {
            close(input[0]); close(input[1])
            throw ProcessSpawnerError.failed(errno: errno)
        }
        // Bubo's ends of the pipes stay out of every other child.
        _ = fcntl(input[1], F_SETFD, FD_CLOEXEC)
        _ = fcntl(output[0], F_SETFD, FD_CLOEXEC)
        defer { close(input[0]); close(output[1]) }

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_adddup2(&actions, input[0], STDIN_FILENO)
        posix_spawn_file_actions_adddup2(&actions, output[1], STDOUT_FILENO)
        if mergingErrors {
            posix_spawn_file_actions_adddup2(&actions, output[1], STDERR_FILENO)
        } else {
            posix_spawn_file_actions_addinherit_np(&actions, STDERR_FILENO)
        }
        if let folder { posix_spawn_file_actions_addchdir(&actions, folder.path) }

        let pid: pid_t
        let isDisclaimed: Bool
        do {
            (pid, isDisclaimed) = try start(executable, arguments: arguments, environment: environment, actions: &actions)
        } catch {
            close(input[1]); close(output[0])
            throw error
        }
        return SpawnedProcess(
            pid: pid,
            input: FileHandle(fileDescriptor: input[1], closeOnDealloc: true),
            output: FileHandle(fileDescriptor: output[0], closeOnDealloc: true),
            isDisclaimed: isDisclaimed
        )
    }

    /// Starts `executable` in `folder` with `terminal`, the subordinate side of a pseudo-terminal, on its standard
    /// input, output and error, and every signal back to its default action.
    ///
    /// - Returns: The child's process identifier.
    /// - Throws: ``ProcessSpawnerError`` if the process cannot start.
    static func spawn(_ executable: URL, arguments: [String] = [], environment: [String: String],
                      terminal: Int32, in folder: URL) throws -> pid_t {
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        for descriptor in [STDIN_FILENO, STDOUT_FILENO, STDERR_FILENO] {
            posix_spawn_file_actions_adddup2(&actions, terminal, descriptor)
        }
        posix_spawn_file_actions_addchdir(&actions, folder.path)
        return try start(executable, arguments: arguments, environment: environment, actions: &actions,
                         resettingSignals: true).pid
    }

    /// `posix_spawn` with the disclaim and only the descriptors of `actions` open in the child.
    private static func start(_ executable: URL, arguments: [String], environment: [String: String],
                              actions: inout posix_spawn_file_actions_t?,
                              resettingSignals: Bool = false) throws -> (pid: pid_t, isDisclaimed: Bool) {
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        // Only the descriptors of `actions` reach the child.
        var flags = Int16(POSIX_SPAWN_CLOEXEC_DEFAULT)
        if resettingSignals {
            // Signals Bubo ignores or blocks, like SIGPIPE, would stay ignored in everything the child runs.
            var all = sigset_t()
            var none = sigset_t()
            sigfillset(&all)
            sigemptyset(&none)
            posix_spawnattr_setsigdefault(&attributes, &all)
            posix_spawnattr_setsigmask(&attributes, &none)
            flags |= Int16(POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK)
        }
        posix_spawnattr_setflags(&attributes, flags)
        let isDisclaimed = disclaim(&attributes)

        let argv = ([executable.path] + arguments).map { strdup($0) } + [nil]
        let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { (argv + envp).forEach { free($0) } }

        var pid: pid_t = 0
        let status = posix_spawn(&pid, executable.path, &actions, &attributes, argv, envp)
        guard status == 0 else { throw ProcessSpawnerError.failed(errno: status) }
        return (pid, isDisclaimed)
    }

    /// Waits for `pid` to exit, off the main thread, and returns its exit status.
    @concurrent
    static func waitForExit(of pid: pid_t) async -> Int32 {
        var status: Int32 = 0
        while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
        return (status & 0x7f) == 0 ? (status >> 8) & 0xff : -(status & 0x7f)
    }

    private typealias SetDisclaim = @convention(c) (UnsafeMutablePointer<posix_spawnattr_t?>, Int32) -> Int32

    /// `responsibility_spawnattrs_setdisclaim`, a private SPI used by Chromium, Firefox, LLDB and Qt Creator.
    private static let setDisclaim: SetDisclaim? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_spawnattrs_setdisclaim")
        else { return nil }
        return unsafeBitCast(symbol, to: SetDisclaim.self)
    }()

    private static func disclaim(_ attributes: UnsafeMutablePointer<posix_spawnattr_t?>) -> Bool {
        guard let setDisclaim, setDisclaim(attributes, 1) == 0 else {
            // ADR 0005 fallback: the child inherits Bubo's permissions; only the Microphone is ever granted.
            Logger.agent.fault("Responsibility disclaim unavailable: the child inherits Bubo's permissions")
            return false
        }
        return true
    }
}

extension Logger {
    nonisolated static let agent = Logger(subsystem: "com.mgiuditta.bubo", category: "agent")
}
