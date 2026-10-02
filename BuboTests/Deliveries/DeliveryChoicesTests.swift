import Foundation
import Testing
@testable import Bubo

/// What keeps Condividi… off in the foglio di Consegna.
struct DeliveryChoicesTests {
    let verified = ReceivedTicket(id: UUID(), person: "Ada", machine: "MacBook", publicKey: Data([1]), status: .verified,
                                  verifiedAt: .now)
    let changed = ReceivedTicket(id: UUID(), person: "Ada", machine: "iMac", publicKey: Data([2]), status: .keyChanged,
                                 verifiedAt: .now)
    let secret = SecretScanner.Finding(ruleID: "github-pat", source: .knownPrefix, value: "ghp_finto0000000000000000",
                                       locations: [])
    let other = SecretScanner.Finding(ruleID: "env:TOKEN", source: .envFile, value: "finto-token-1234", locations: [])

    @Test func shareIsOffWithoutARecipient() {
        let choices = DeliveryChoices(findings: [])

        #expect(choices.missing == .recipient)
        #expect(!choices.canShare)
    }

    @Test func shareIsOffWhileASecretIsUndecided() {
        var choices = DeliveryChoices(findings: [secret, other])
        choices.choose(verified)
        choices.decide(.keep, for: secret.id)

        #expect(choices.missing == .decisions(1))
        #expect(choices.undecidedCount == 1)
        #expect(!choices.canShare)

        choices.decide(.remove, for: other.id)
        #expect(choices.canShare)
        #expect(choices.removedSecrets == [other.value])
    }

    @Test func aTicketWithAChangedKeyIsNotChosen() {
        var choices = DeliveryChoices(findings: [])

        let isChosen = choices.choose(changed)

        #expect(!isChosen)
        #expect(choices.recipient == nil)
    }

    @Test func aRecipientWhoseKeyChangedMeanwhileIsForgotten() {
        var choices = DeliveryChoices(findings: [])
        choices.choose(verified)
        var now = verified
        now.status = .keyChanged

        choices.keepRecipient(among: [now])

        #expect(choices.missing == .recipient)
    }

    @Test func removingASecretThatIsAlsoInTheUncommittedChangesKeepsShareOff() {
        var choices = DeliveryChoices(findings: [secret], findingsInBranch: [secret.id])
        choices.choose(verified)
        choices.decide(.remove, for: secret.id)

        #expect(choices.missing == .removalsInBranch(1))

        choices.decide(.keep, for: secret.id)
        #expect(choices.canShare)
    }
}
