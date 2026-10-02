import os
import SwiftUI

/// The pull request of a Sessione In revisione, on its card and in the Sessione (spec 16): its number, linked to
/// GitHub, its checks as last read, Correggi when one failed and Aggiorna PR when the Sessione has work the pull
/// request lacks. Nothing is pushed without Aggiorna PR.
struct PullRequestBadge: View {
    let session: Session
    let store: SessionStore
    @State private var isFixing = false
    /// Why Apri nel terminale failed.
    @State private var terminalFailure: String?

    private var status: PullRequestStatus? { store.pullRequests.statuses[session.id] }

    var body: some View {
        if let pullRequest = session.pullRequest {
            VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                HStack(spacing: Spacing.xSmall) {
                    Link(pullRequest.label, destination: pullRequest.url)
                        .help("Apre la PR su GitHub")
                    if let status, let checks = Self.checksSummary(of: status.checks) {
                        Label {
                            Text(verbatim: checks.text)
                        } icon: {
                            Image(systemName: checks.symbol)
                                .foregroundStyle(checks.color)
                        }
                        .font(Typography.body(size: 12))
                        .foregroundStyle(Palette.textSecondary)
                    }
                }
                if let status, status.isBehind {
                    Text("La Sessione ha modifiche che la PR non ha.")
                        .font(Typography.body(size: 12))
                        .foregroundStyle(Palette.textSecondary)
                }
                actions
                if let failure = store.pullRequests.updateFailures[session.id] {
                    Text(verbatim: terminalFailure ?? failure.message)
                        .font(Typography.body(size: 12))
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(4)
                        .textSelection(.enabled)
                    if let remedy = failure.remedy {
                        Button("Apri nel terminale") { openTerminal(typing: remedy) }
                            .help("Apre il Terminale con «\(remedy)» già scritto: premi Invio per eseguirlo")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        let hasFailed = status?.failedChecks.isEmpty == false
        let isBehind = status?.isBehind == true
        if hasFailed || isBehind {
            HStack(spacing: Spacing.xSmall) {
                if hasFailed {
                    Button("Correggi", action: fix)
                        .disabled(session.isRunning || isFixing)
                        .help("Manda all'agente i check falliti, con il loro log, come nuovo turno")
                }
                if isBehind {
                    Button("Aggiorna PR", action: update)
                        .disabled(session.isRunning || store.pullRequests.updating.contains(session.id))
                        .help("Fa il push delle modifiche nuove sul branch della PR")
                }
            }
        }
    }

    /// The checks in a few words, with their symbol and color; `nil` without checks.
    static func checksSummary(of checks: [PullRequestCheck])
        -> (text: String, symbol: String, color: Color)? {
        let counted = checks.filter { $0.outcome != .skipped }
        guard !counted.isEmpty else { return nil }
        let total = counted.count
        let failed = counted.count { $0.outcome == .failed }
        let pending = counted.count { $0.outcome == .pending }
        if failed > 0 {
            return (String(localized: "Check falliti: \(failed) su \(total)"), "xmark.circle.fill", Palette.danger)
        }
        if pending > 0 {
            return (String(localized: "Check in corso: \(pending) su \(total)"), "clock", Palette.attention)
        }
        return (String(localized: "Check passati: \(total) su \(total)"), "checkmark.circle.fill", Palette.success)
    }

    private func fix() {
        isFixing = true
        Task {
            defer { isFixing = false }
            await store.fixChecks(of: session.id)
        }
    }

    private func update() {
        terminalFailure = nil
        Task { await store.requestPullRequestUpdate(of: session.id) }
    }

    private func openTerminal(typing command: String) {
        do {
            try SystemTerminal().open(typing: command)
        } catch {
            Logger.sessions.error("Terminal not opened: \(String(describing: error), privacy: .public)")
            terminalFailure = error.localizedDescription
        }
    }
}
