import RemoteKit
import SwiftUI

/// A Richiesta in Attende te: Progetto and title, reason, tool and command, the time left, and its answers.
///
/// Levels 1–3: No, Solo ora and, where the Mac offers it, Per questa Sessione as the primary button. Levels 4–5 and
/// what needs a careful read: only Rivedi e decidi, which opens the full-screen page. VoiceOver reads the tile as
/// one element, with the answers as its actions.
struct RequestTile: View {
    let waiting: WaitingRequest
    /// Whether to name the Mac: more than one is paired.
    let showsMac: Bool
    let decide: (WaitingRequest, Verdict.Answer) async -> Void
    let review: () -> Void
    @State private var isDeciding = false

    private var request: RemoteRequest { waiting.request }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RequestSummary(waiting: waiting, showsMac: showsMac)
            if let subject = request.subject {
                Text(verbatim: subject)
                    .font(.callout.monospaced())
                    .lineLimit(4)
            }
            RequestDeadline(request: request)
            buttons
                .disabled(isDeciding)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(request.project), \(request.sessionTitle)"))
        .accessibilityValue(accessibilityValue)
        .accessibilityActions {
            if request.needsReview {
                Button("Rivedi e decidi", action: review)
            } else {
                ForEach(request.answers, id: \.self) { answer in
                    Button(answer.buttonTitle) { Task { await answerWith(answer) } }
                }
            }
        }
    }

    @ViewBuilder private var buttons: some View {
        if request.needsReview {
            Button("Rivedi e decidi", action: review)
                .buttonStyle(.borderedProminent)
        } else {
            HStack {
                Button("No", role: .destructive) { Task { await answerWith(.deny) } }
                    .buttonStyle(.bordered)
                Button("Solo ora") { Task { await answerWith(.allowOnce) } }
                    .buttonStyle(.bordered)
                if request.answers.contains(.allowForSession) {
                    Button("Per questa Sessione") { Task { await answerWith(.allowForSession) } }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private var accessibilityValue: Text {
        let level = Text("Livello \(request.level)")
        let reason = Text(verbatim: request.reason ?? request.tool)
        let subject = Text(verbatim: request.subject ?? "")
        return Text("\(level). \(reason). \(subject)")
    }

    private func answerWith(_ answer: Verdict.Answer) async {
        isDeciding = true
        await decide(waiting, answer)
        isDeciding = false
    }
}

/// Progetto and title of a Richiesta, the Mac when more than one is paired, then its reason or tool.
struct RequestSummary: View {
    let waiting: WaitingRequest
    let showsMac: Bool

    var body: some View {
        let request = waiting.request
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: showsMac ? "\(request.project) · \(waiting.macName)" : request.project)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(verbatim: request.sessionTitle)
                .font(.headline)
            Text(verbatim: request.reason ?? request.tool)
                .font(.subheadline)
        }
    }
}

/// "Livello N · scade tra N min", or that only the Mac can decide it now.
struct RequestDeadline: View {
    let request: RemoteRequest

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Group {
                if request.isExpired(at: context.date) {
                    Text("Livello \(request.level) · scaduta: rispondi dal Mac")
                } else {
                    let left = Duration.seconds(max(60, request.expiresAt.timeIntervalSince(context.date)))
                    Text("Livello \(request.level) · scade tra \(left.formatted(.units(allowed: [.minutes], width: .abbreviated)))")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }
}

extension Verdict.Answer {
    /// The title of the button that gives this answer.
    var buttonTitle: LocalizedStringResource {
        switch self {
        case .deny: "No"
        case .allowOnce: "Solo ora"
        case .allowForSession: "Per questa Sessione"
        }
    }
}
