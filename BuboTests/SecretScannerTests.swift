import Foundation
import Testing
@testable import Bubo

struct SecretScannerTests {
    let corpus = DeliveryCorpus.shared

    func scanner() throws -> SecretScanner {
        try #require(SecretScanner.bundled)
    }

    @Test func theRulesComeFromThePinnedGitleaksVersion() throws {
        let scanner = try scanner()

        #expect(scanner.version == "v8.30.1")
        // Go's RE2 and ICU agree on almost everything; what does not compile is listed, not lost silently.
        #expect(scanner.skippedRules == ["jwt-base64", "kubernetes-secret-yaml"])
    }

    @Test func everyPlantedSecretOfTheCorpusIsFoundOnce() throws {
        let findings = try scanner().scan(DeliveryCorpus.session())

        for (rule, secret) in corpus.secrets {
            let matching = findings.filter { $0.value == secret }
            #expect(matching.count == 1, "\(rule)")
            #expect(matching.first?.ruleID == rule)
        }
    }

    @Test func theReportCountsFoundSecretsAndFalsePositives() throws {
        let findings = try scanner().scan(DeliveryCorpus.session())
        let planted = Set(corpus.secrets.values)
        let found = findings.filter { planted.contains($0.value) }
        let falsePositives = findings.filter { !planted.contains($0.value) }
        let missed = corpus.missed.filter { secret in !findings.contains { $0.value == secret } }
        let report = """
        Scanner \((try? scanner().version) ?? "?") on the Consegna corpus
        found: \(found.count) of \(planted.count) planted; still missed as expected: \(missed.count) of \(corpus.missed.count)
        false positives: \(falsePositives.count)
        \(falsePositives.map { "  \($0)" }.joined(separator: "\n"))
        """
        Attachment.record(report, named: "scanner-report.txt")

        #expect(found.count == planted.count)
        #expect(missed.count == corpus.missed.count)
        #expect(falsePositives.isEmpty)
        // The report shows no secret in clear.
        for secret in planted { #expect(!report.contains(secret)) }
    }

    @Test func aSecretSeenInManyPlacesIsOneFindingWithEveryPlace() throws {
        let token = try #require(corpus.secrets["github-pat"])
        let documents = [
            SecretScanner.Document(text: "origin https://x:\(token)@github.com/ada/telaio.git", location: .init(file: "a", line: 3)),
            SecretScanner.Document(text: "Il token \(token) è scaduto.", location: .init(file: "a", line: 9)),
            SecretScanner.Document(text: "Prima riga\nGITHUB_TOKEN: \(token)", location: .init(file: "b", line: 1)),
        ]

        let findings = try scanner().scan(documents)

        #expect(findings.count == 1)
        #expect(findings.first?.locations.map(\.line) == [3, 9, 2])
        #expect(findings.first?.source == .knownPrefix)
    }

    @Test func theEnvFileValuesTheSessionReadAreFindings() throws {
        let findings = try scanner().scan(DeliveryCorpus.session())

        let env = findings.filter { $0.source == .envFile }

        #expect(Set(env.map(\.ruleID)) == ["env:DATABASE_PASSWORD", "env:SESSION_SECRET"])
    }

    @Test func aFindingNeverShowsItsValue() throws {
        let findings = try scanner().scan(DeliveryCorpus.session())

        for finding in findings {
            var dumped = ""
            dump(finding, to: &dumped)
            for text in [String(describing: finding), String(reflecting: finding), "\(finding)", dumped] {
                #expect(!text.contains(finding.value), "\(finding)")
            }
            #expect(finding.maskedExcerpt == String(finding.value.prefix(4)) + "…")
        }
    }

    @Test func whatTheScannerFindsTheCleanerTakesOut() throws {
        let session = try DeliveryCorpus.session()
        let findings = try scanner().scan(session)
        let cleaner = TranscriptCleaner(sender: corpus.sender, newSessionID: "n", removedSecrets: Set(findings.map(\.value)))

        let cleaned = try cleaner.cleaning(session)

        #expect(try scanner().scan(cleaned.files).isEmpty)
    }

    @Test func envAssignmentsSkipPortsFlagsAndComments() {
        let text = """
             1→# Database
             2→DATABASE_URL="postgres://localhost/telaio"
             3→PORT=8080
             4→export API_TOKEN='abc123xyz'
             5→DEBUG=true
        """

        let values = SecretScanner.envAssignments(in: text)

        #expect(values.map(\.name) == ["DATABASE_URL", "API_TOKEN"])
        #expect(values.map(\.value) == ["postgres://localhost/telaio", "abc123xyz"])
    }

    @Test(arguments: [
        "Commit 9f3c2a1b4d5e6f708192a3b4c5d6e7f809a1b2c3 su main.",
        "La Sessione 3F2504E0-4F89-11D3-9A0C-0305E82C3301 è Fusa.",
        "let tokenCount = tokens.count + 1",
        "func makeSecretFilter() -> SecretFilter { SecretFilter() }",
        "https://github.com/mgiuditta/bubo/pull/118",
        "Costa 0,42 € e ha usato 12.345 token.",
        "apiVersion: 2023-06-01",
    ])
    func commitHashesUUIDsAndCodeAreNoFindings(_ text: String) throws {
        let document = SecretScanner.Document(text: text, location: .init(file: "t", line: 1))

        #expect(try scanner().scan([document]).isEmpty)
    }

    @Test func mostSecretsOfTheMemoryTranscriptsAreFound() throws {
        let scanner = try scanner()
        let transcripts = PlantedSecrets.all
        var found = 0
        var total = 0

        for transcript in transcripts {
            let documents = transcript.messages.enumerated().map { index, message in
                SecretScanner.Document(text: message.text, location: .init(file: transcript.titolo, line: index + 1))
            }
            let values = scanner.scan(documents).map(\.value)
            total += transcript.secrets.count
            found += transcript.secrets.count { secret in values.contains { $0.contains(secret) || secret.contains($0) } }
        }
        Attachment.record("found \(found) of \(total) secrets of SecretFilterTests' set", named: "scanner-memory-set.txt")

        // 19 of 25 with gitleaks v8.30.1: it misses low-entropy passwords and values without a prefix, which the
        // obligatory preview is there for.
        #expect(found >= 19)
    }
}
