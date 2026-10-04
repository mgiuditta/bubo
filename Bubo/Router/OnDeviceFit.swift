/// What Apple's on-device model can take of a Domanda, measured before the router decides.
nonisolated enum OnDeviceFit: Equatable, Sendable {
    /// Within the limit, as the model counted it.
    case fits(tokens: Int)
    /// Over the limit, as the model counted it.
    case tooLong(tokens: Int)
    /// No count: macOS before 26.4 has no `tokenCount(for:)`, or the count failed or ran past its budget.
    case notMeasurable
    /// Apple Intelligence off, the Mac not eligible, or the model not ready.
    case unavailable
}
