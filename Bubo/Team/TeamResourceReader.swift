import CoreServices
import Foundation
import os

/// The Regole di permesso of a Progetto's `.bubo/regole.json` and what the user decided about each, kept fresh with
/// FSEvents (ADR 0009).
///
/// Only the main checkout counts: a change in a Sessione's worktree applies once it gets there.
@Observable
final class TeamResourceReader {
    /// What the file holds.
    nonisolated enum State: Equatable {
        /// Not read yet.
        case loading
        /// No `.bubo/regole.json`.
        case missing
        /// The file exists but cannot be read: no team rule applies, not even `deny`.
        case unreadable
        case rules(TeamRules)
    }

    /// An `allow` of the file, with what the user needs to decide on it.
    nonisolated struct Voce: Identifiable, Equatable {
        var id: String { hash }
        /// The normalized rule.
        let rule: String
        let hash: String
        /// The worst call the rule would allow; levels 4–5 are never accepted.
        let risk: Risk
        /// What the user decided about this exact text; `nil` when it is still to look at.
        let decision: TrustLedger.Decision?
        /// The text accepted before, when this one looks like a change of it.
        let previous: String?

        /// Whether the rule may be accepted at all.
        var isAcceptable: Bool { !risk.level.isDangerous && !risk.isCritical }
    }

    /// The Progetto's main checkout.
    let root: URL
    private(set) var state = State.loading
    private(set) var voci: [Voce] = []
    /// The author of the last commit that touched each rule, by rule; missing while unknown or never committed.
    private(set) var authors: [String: String] = [:]

    @ObservationIgnored private let ledger: TrustLedger
    @ObservationIgnored private let runner: ProcessRunner

    /// Creates a reader of the Progetto `project`, or of the Progetto it is a worktree of.
    init(project: URL, ledger: TrustLedger = .standard, runner: ProcessRunner = .live) {
        root = URL(filePath: TrustGate.root(of: project), directoryHint: .isDirectory)
        self.ledger = ledger
        self.runner = runner
    }

    /// The voci still to look at: neither accepted nor ignored.
    var pendingCount: Int { voci.count { $0.decision == nil } }

    /// The `deny` and `ask` in force, empty unless the file is read.
    var rules: TeamRules {
        guard case let .rules(rules) = state else { return TeamRules() }
        return rules
    }

    /// Reads the file and the decisions again.
    func reload() {
        let state: State
        do {
            state = try TeamRules.read(inProject: root).map(State.rules) ?? .missing
        } catch {
            Logger.team.error("Team rules unreadable: \(String(describing: error), privacy: .public)")
            state = .unreadable
        }
        self.state = state
        voci = Self.voci(of: rules, entries: ledger.entries(inProject: root.path),
                         classifier: RiskClassifier(workingDirectory: root))
    }

    /// Reads the file, then again each time something under `.bubo` changes, until the task is cancelled.
    func watch() async {
        reload()
        await readAuthors()
        for await batch in FileEvents.batches(under: root.path, since: FSEventStreamEventId(kFSEventStreamEventIdSinceNow)) {
            let folder = root.appending(path: ".bubo").path
            guard batch.needsRescan || batch.paths.contains(where: { $0 == folder || $0.hasPrefix(folder + "/") }) else {
                continue
            }
            reload()
            await readAuthors()
        }
    }

    /// Accetta: `voce` applies from the next turn of every Sessione of the Progetto.
    ///
    /// - Throws: A file error from the ledger.
    func accept(_ voce: Voce) throws {
        guard voce.isAcceptable else { return }
        try ledger.record(.accepted, about: voce.rule, inProject: root.path)
        reload()
    }

    /// Ignora: `voce` does not apply and is no longer to look at, until it changes.
    ///
    /// - Throws: A file error from the ledger.
    func ignore(_ voce: Voce) throws {
        try ledger.record(.ignored, about: voce.rule, inProject: root.path)
        reload()
    }

    /// The team rules a `claude` started in `folder` gets as session rules: `deny` and `ask` as they are, the `allow`
    /// the user accepted with exactly this text and below level 4. None when the file is missing or unreadable.
    nonisolated static func sessionRules(for folder: URL, ledger: TrustLedger = .standard) -> TeamRules {
        let root = URL(filePath: TrustGate.root(of: folder), directoryHint: .isDirectory)
        guard let rules = try? TeamRules.read(inProject: root) else { return TeamRules() }
        let voci = voci(of: rules, entries: ledger.entries(inProject: root.path),
                        classifier: RiskClassifier(workingDirectory: root))
        return TeamRules(allow: voci.filter { $0.decision == .accepted && $0.isAcceptable }.map(\.rule),
                         deny: rules.deny, ask: rules.ask)
    }

    /// The `allow` of `rules` with their risk, the decision about their exact text and, for a voce still to look at,
    /// the accepted text it most likely replaces: one for the same tool that is no longer in the file.
    nonisolated static func voci(of rules: TeamRules, entries: [TrustLedger.Entry],
                                 classifier: RiskClassifier) -> [Voce] {
        let gone = entries.filter { $0.decision == .accepted && !rules.allow.contains($0.text) }
        return rules.allow.map { rule in
            let hash = TeamRules.hash(of: rule)
            let decision = entries.last { $0.hash == hash }?.decision
            let tool = RiskClassifier.parts(of: rule).tool
            let previous = decision == nil ? gone.last { RiskClassifier.parts(of: $0.text).tool == tool }?.text : nil
            return Voce(rule: rule, hash: hash, risk: classifier.risk(ofRule: rule), decision: decision,
                        previous: previous)
        }
    }

    private static let spelling = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        return encoder
    }()

    /// Asks git who last committed each `allow`; a rule never committed has no author.
    private func readAuthors() async {
        var authors: [String: String] = [:]
        for voce in voci {
            // The rule as the file spells it, quotes and backslashes escaped.
            guard let encoded = try? Self.spelling.encode(voce.rule),
                  let spelled = String(data: encoded, encoding: .utf8)?.dropFirst().dropLast()
            else { continue }
            let arguments = ["-C", root.path, "log", "-1", "--no-textconv", "--no-ext-diff", "--format=%an",
                             "-S", String(spelled), "--", TeamRules.path]
            guard let output = try? await runner.run(URL(filePath: "/usr/bin/git"), arguments), output.exitCode == 0
            else { continue }
            let author = output.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            if !author.isEmpty { authors[voce.rule] = author }
        }
        self.authors = authors
    }
}

extension Logger {
    nonisolated static let team = Logger(subsystem: "com.mgiuditta.bubo", category: "team")
}
