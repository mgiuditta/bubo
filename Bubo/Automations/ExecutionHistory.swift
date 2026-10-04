import SwiftUI

/// The Esecuzioni of an Automazione, newest first, folded under its row: one line each, also the Saltate, with
/// Apri Sessione for those whose Sessione is still in the Vista (spec 19).
struct ExecutionHistory: View {
    let executions: [Execution]
    /// Opens the HUD on the Sessione of an Esecuzione; `nil` when that Sessione is gone or archived.
    let openSession: (UUID) -> (() -> Void)?
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                ForEach(Array(executions.reversed().enumerated()), id: \.offset) { _, execution in
                    line(execution)
                }
            }
            .padding(.top, Spacing.xxSmall)
        } label: {
            Text("Storico (\(executions.count))")
                .font(Typography.body(size: 11))
                .foregroundStyle(Palette.textSecondary)
        }
    }

    private func line(_ execution: Execution) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xSmall) {
            Text(summary(of: execution))
                .font(Typography.body(size: 11))
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Spacing.xSmall)
            if let session = execution.session, let open = openSession(session) {
                Button("Apri Sessione", action: open)
                    .buttonStyle(.link)
                    .font(Typography.body(size: 11))
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// When it started, how it went and, once it started, how many actions were denied.
    private func summary(of execution: Execution) -> String {
        let time = execution.startedAt.formatted(date: .abbreviated, time: .shortened)
        guard execution.outcome != .saltata else { return String(localized: "\(time) · \(execution.title)") }
        return String(localized: "\(time) · \(execution.title) · \(execution.denialCount) negate")
    }
}

#Preview {
    ExecutionHistory(executions: [
        Execution(startedAt: .now.addingTimeInterval(-86_400), outcome: .saltata, skipReason: .assente),
        Execution(startedAt: .now.addingTimeInterval(-3_600), session: UUID(), outcome: .fatta, denialCount: 2),
    ]) { _ in {} }
    .padding()
    .background(Palette.ink)
}
