import Foundation

/// What the user chose in the foglio di Consegna (spec 24, Interfaccia): the Macchina it goes to and a decision for
/// each possible secret. Condividi… stays off until nothing is missing, and the foglio says what is.
nonisolated struct DeliveryChoices: Sendable {
    /// What the user decided for one possible secret. There is no default: every one is decided by hand.
    enum Decision: Equatable, Sendable {
        /// Togli: the value becomes `‹tolto›` in the conversation, the subagent and the tool results.
        case remove
        /// Lascia: the value goes out as it is.
        case keep
    }

    /// What still keeps Condividi… off, the first first.
    enum Missing: Equatable, Sendable {
        /// No Macchina chosen.
        case recipient
        /// Possible secrets with no decision yet, this many.
        case decisions(Int)
        /// Secrets decided Togli that are also in the uncommitted changes, which Togli does not touch: this many.
        case removalsInBranch(Int)
    }

    /// The Biglietto of the Macchina it goes to; only a verified one can be chosen.
    private(set) var recipient: ReceivedTicket.ID?
    /// The decision for each possible secret, by its id.
    private(set) var decisions: [SecretScanner.Finding.ID: Decision] = [:]

    /// The possible secrets the foglio lists.
    let findings: [SecretScanner.Finding]
    /// The ids of the findings found in the uncommitted changes of the branch.
    let findingsInBranch: Set<SecretScanner.Finding.ID>

    /// Creates the choices for `findings`, of which `findingsInBranch` are in the uncommitted changes.
    init(findings: [SecretScanner.Finding], findingsInBranch: Set<SecretScanner.Finding.ID> = []) {
        self.findings = findings
        self.findingsInBranch = findingsInBranch
    }

    /// Chooses the Macchina of `ticket`; a Biglietto whose key changed is not chosen.
    ///
    /// - Returns: Whether the Macchina is now the recipient.
    @discardableResult
    mutating func choose(_ ticket: ReceivedTicket) -> Bool {
        guard ticket.status == .verified else { return false }
        recipient = ticket.id
        return true
    }

    /// Forgets the recipient when its Biglietto is no longer among `tickets`, or no longer verified.
    mutating func keepRecipient(among tickets: [ReceivedTicket]) {
        guard let recipient, !tickets.contains(where: { $0.id == recipient && $0.status == .verified }) else { return }
        self.recipient = nil
    }

    /// Decides `decision` for the possible secret `id`.
    mutating func decide(_ decision: Decision, for id: SecretScanner.Finding.ID) {
        decisions[id] = decision
    }

    /// How many possible secrets have no decision yet: the counter of Da decidere.
    var undecidedCount: Int {
        findings.count { decisions[$0.id] == nil }
    }

    /// What keeps Condividi… off, the first first; `nil` when it can go.
    var missing: Missing? {
        if recipient == nil { return .recipient }
        if undecidedCount > 0 { return .decisions(undecidedCount) }
        let blocked = findingsInBranch.count { decisions[$0] == .remove }
        return blocked > 0 ? .removalsInBranch(blocked) : nil
    }

    /// Whether Condividi… can go.
    var canShare: Bool { missing == nil }

    /// The values decided Togli, for ``TranscriptCleaner``.
    var removedSecrets: Set<String> {
        Set(findings.filter { decisions[$0.id] == .remove }.map(\.value))
    }
}
