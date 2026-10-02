import Foundation

extension RemoteChannel {
    /// Seals `verdict` with the pair's key and saves it for the Mac, which reads it with
    /// ``verdicts(macID:deviceID:sealer:)``.
    public func send(_ verdict: SignedVerdict, sealer: RecordSealer) async throws {
        let id = sealer.recordID(named: "verdict/" + verdict.verdict.nonce.base64EncodedString())
        try await save(RemoteRecord(
            id: id,
            kind: .verdict,
            macID: verdict.verdict.macID,
            deviceID: verdict.deviceID,
            expiresAt: verdict.verdict.issuedAt.addingTimeInterval(VerdictVerifier.maximumAge),
            payload: sealer.seal(verdict, recordID: id)
        ))
    }

    /// The Verdicts the iPhone `deviceID` wrote for the Mac `macID`, each with its record ID; `nil` for a record
    /// that does not open, which the Mac deletes all the same.
    public func verdicts(macID: UUID, deviceID: UUID, sealer: RecordSealer) async throws
        -> [(recordID: String, verdict: SignedVerdict?)] {
        try await records(macID: macID, deviceID: deviceID)
            .filter { $0.kind == .verdict }
            .map { ($0.id, try? sealer.open(SignedVerdict.self, from: $0.payload, recordID: $0.id)) }
    }
}
