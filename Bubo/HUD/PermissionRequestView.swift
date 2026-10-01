import SwiftUI

/// A Richiesta di permesso inside its Sessione: the Livello di rischio, what `claude` wants to do, and the answers.
///
/// Levels 1–3 take one key: ↩ Solo ora, esc No. Levels 4–5 open on No and approve only with a 1-second press,
/// with no "Per questa Sessione" nor "Sempre in questo Progetto", which first shows the rule it would save.
struct PermissionRequestView: View {
    let pending: RequestCenter.Pending
    /// The folder of the Sessione's Progetto, where "Sempre in questo Progetto" saves its rule.
    let project: URL
    /// How many more Richieste of the Sessione wait behind this one.
    let queued: Int
    /// Whether ↩ and esc answer it: only the oldest Richiesta across the Sessioni, so one key never answers two.
    let hasKeyboard: Bool
    let answer: (PermissionAnswer) -> Void
    /// Saves the Richiesta's rule in the Progetto, then allows the call.
    var allowInProject: () throws -> Void = {}
    @State private var isShowingRule = false

    private var request: PermissionRequest { pending.request }
    private var color: Color { pending.risk.level.isDangerous ? Palette.danger : Palette.attention }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
            HStack(alignment: .firstTextBaseline) {
                Text("Livello \(pending.risk.level.rawValue) · \(Text(pending.risk.level.title))")
                    .font(Typography.mono(size: 10, weight: .medium))
                    .textCase(.uppercase)
                    .foregroundStyle(color)
                Spacer(minLength: Spacing.xSmall)
                if queued > 0 {
                    Text("In coda: \(queued)")
                        .font(Typography.mono(size: 10))
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            Text(verbatim: request.title ?? request.tool)
                .font(Typography.body(size: 12, weight: .semibold))
                .lineLimit(3)
            if let subject = request.command ?? request.path ?? request.url {
                // Tutto quello che verrà eseguito, invisibili e controlli scritti per esteso: niente righe tagliate.
                ScrollView {
                    Text(verbatim: Self.shown(subject))
                        .font(Typography.mono(size: 11))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
                .fixedSize(horizontal: false, vertical: true)
                .padding(Spacing.xxSmall)
                .background(Palette.ink.opacity(0.6), in: .rect(cornerRadius: CornerRadius.small))
            }
            if let detail = request.detail {
                Text(verbatim: detail)
                    .font(Typography.body(size: 11))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(2)
            }
            if request.isFromSubagent {
                Text("La chiede un subagente.")
                    .font(Typography.body(size: 11))
                    .foregroundStyle(Palette.textSecondary)
            }
            answers
                .padding(.top, Spacing.xxSmall)
        }
        .padding(Spacing.xSmall)
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.small)
                .stroke(color.opacity(0.5), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Richiesta di permesso")
    }

    private var answers: some View {
        HStack(spacing: Spacing.xSmall) {
            Button("No") { answer(.deny) }
                .keyboardShortcut(hasKeyboard ? .cancelAction : nil)
            if pending.needsHold {
                HoldToAllowButton(color: color) { answer(.allowOnce) }
            } else {
                Button("Solo ora") { answer(.allowOnce) }
                    .keyboardShortcut(hasKeyboard ? .defaultAction : nil)
                if pending.allowsSessionRule {
                    Button("Per questa Sessione") { answer(.allowForSession) }
                }
                if pending.projectRule != nil {
                    Button("Sempre in questo Progetto…") { isShowingRule = true }
                }
            }
            Spacer(minLength: 0)
            if hasKeyboard {
                Text(pending.needsHold ? "esc No" : "↩ Solo ora · esc No")
                    .font(Typography.mono(size: 10))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .sheet(isPresented: $isShowingRule) {
            if let rule = pending.projectRule {
                ProjectRuleSheet(rule: rule, project: project, save: allowInProject)
            }
        }
    }

    /// `subject` line by line, each with every control and invisible character escaped as in the trust dialog.
    static func shown(_ subject: String) -> String {
        subject.split(separator: "\n", omittingEmptySubsequences: false)
            .map { RepoActivations.escaped(String($0)) }
            .joined(separator: "\n")
    }
}

/// Approves only after a 1-second press: no key, no single click.
private struct HoldToAllowButton: View {
    let color: Color
    let action: () -> Void
    @State private var isPressing = false

    var body: some View {
        Text("Tieni premuto: Solo ora")
            .font(Typography.body(size: 12, weight: .semibold))
            .padding(.horizontal, Spacing.xSmall)
            .padding(.vertical, 3)
            .background(alignment: .leading) {
                GeometryReader { proxy in
                    color.opacity(0.35)
                        .frame(width: isPressing ? proxy.size.width : 0)
                }
            }
            .clipShape(.rect(cornerRadius: CornerRadius.small))
            .overlay {
                RoundedRectangle(cornerRadius: CornerRadius.small)
                    .stroke(color, lineWidth: 1)
            }
            .contentShape(.rect)
            .onLongPressGesture(minimumDuration: 1, maximumDistance: 20, perform: action) { pressing in
                withAnimation(pressing ? Motion.hold : Motion.quick) { isPressing = pressing }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Consenti solo ora")
            .accessibilityHint("Azione rischiosa: con il puntatore, tieni premuto per un secondo.")
            .accessibilityAction(.default, action)
    }
}

#Preview {
    VStack(spacing: Spacing.small) {
        PermissionRequestView(
            pending: .init(request: PermissionRequest(id: "1", tool: "Bash", command: "npm test"),
                           risk: Risk(level: .modifica), since: .now),
            project: URL(filePath: "/Users/u/Sviluppo/repo"), queued: 2, hasKeyboard: true) { _ in }
        PermissionRequestView(
            pending: .init(request: PermissionRequest(id: "2", tool: "Bash", command: "git push --force origin main"),
                           risk: Risk(level: .irreversibile), since: .now),
            project: URL(filePath: "/Users/u/Sviluppo/repo"), queued: 0, hasKeyboard: false) { _ in }
    }
    .frame(width: 320)
    .padding()
    .background(Palette.ink)
}
