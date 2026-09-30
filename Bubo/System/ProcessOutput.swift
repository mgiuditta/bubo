/// What a finished child process left behind.
struct ProcessOutput: Equatable, Sendable {
    /// The process's exit status; `0` means success.
    var exitCode: Int32
    /// Everything the process wrote to standard output, as UTF-8.
    var standardOutput: String
    /// Everything the process wrote to standard error, as UTF-8.
    var standardError = ""
}
