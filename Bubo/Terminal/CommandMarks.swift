/// What in a terminal's output hints that a server started or stopped (spec 15): an OSC 133 mark, the start or end
/// of a command, or a local URL like the one a dev server prints when it listens.
nonisolated enum CommandMarks {
    /// What is looked for, as bytes: no decoding of the output.
    private static let hints: [[UInt8]] = ["\u{1B}]133;", "localhost:", "127.0.0.1:", "0.0.0.0:", "[::1]:", "[::]:"]
        .map { Array($0.utf8) }

    /// Whether `output` has a mark or a local URL.
    static func hintsAtServer(_ output: ArraySlice<UInt8>) -> Bool {
        hints.contains { output.firstRange(of: $0) != nil }
    }
}
