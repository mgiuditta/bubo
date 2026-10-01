import SwiftUI

/// The diff of the selected file in a glass panel over the map, blocco by blocco as the Sessione's revisione shows
/// it, with "Apri nella revisione della Sessione" (spec 11). Nothing when no Sessione wrote or changed the file.
struct GalaxyDiffPanel: View {
    let model: GalaxyModel
    /// Opens the revisione of the Sessione at the file's path; `nil` when it cannot open.
    let openReview: ((UUID, String) -> Void)?

    var body: some View {
        let diff = model.diff
        ZStack {
            if let diff {
                panel(diff)
                    .transition(.opacity)
            }
        }
        .animation(Motion.isReduced ? nil : Motion.standard, value: diff?.path)
    }

    private func panel(_ diff: GalaxyModel.Diff) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            header(diff)
            if diff.sessions.count > 1 {
                sessionPicker(diff)
            }
            content(diff)
            if let openReview, diff.session.isReviewable {
                Button("Apri nella revisione della Sessione") { openReview(diff.session.id, diff.path) }
                    .controlSize(.small)
                    .help("Apre la revisione di questa Sessione su questo file, blocco per blocco")
            }
        }
        .padding(Spacing.small)
        .frame(maxWidth: 560, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: CornerRadius.panel))
        .padding(Spacing.small)
        .onExitCommand { model.closeDiff() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Diff di \((diff.path as NSString).lastPathComponent)"))
    }

    private func header(_ diff: GalaxyModel.Diff) -> some View {
        let file = diff.path as NSString
        return HStack(alignment: .firstTextBaseline, spacing: Spacing.xSmall) {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: file.lastPathComponent)
                    .font(Typography.body(size: 13, weight: .medium))
                    .accessibilityAddTraits(.isHeader)
                if !file.deletingLastPathComponent.isEmpty {
                    Text(verbatim: file.deletingLastPathComponent)
                        .font(Typography.mono(size: 10))
                        .foregroundStyle(Palette.textSecondary)
                        .truncationMode(.head)
                }
            }
            .lineLimit(1)
            Spacer(minLength: Spacing.xSmall)
            if case let .file(changed?) = diff.content {
                let hunks = changed.hunks
                Text(verbatim: "+\(hunks.reduce(0) { $0 + $1.added }) −\(hunks.reduce(0) { $0 + $1.removed })")
                    .font(Typography.mono(size: 11))
                    .foregroundStyle(Palette.textSecondary)
                    .monospacedDigit()
            }
            Button("Chiudi il diff", systemImage: "xmark") { model.closeDiff() }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Chiudi il diff")
        }
    }

    /// One button per Sessione that wrote or changed the file: a collision has more than one diff.
    private func sessionPicker(_ diff: GalaxyModel.Diff) -> some View {
        HStack(spacing: Spacing.xxSmall) {
            ForEach(diff.sessions) { session in
                let isShown = session.id == diff.session.id
                Button { model.showDiff(of: session.id) } label: {
                    Text(verbatim: "\(session.sign) \(session.title)")
                        .lineLimit(1)
                        .frame(maxWidth: 160)
                }
                .buttonStyle(.bordered)
                // The container stays achromatic (ADR 0004).
                .tint(isShown ? Palette.textPrimary : nil)
                .accessibilityLabel(Text(verbatim: session.title))
                .accessibilityAddTraits(isShown ? .isSelected : [])
                .help("Mostra il diff di questa Sessione")
            }
        }
        .controlSize(.small)
    }

    @ViewBuilder
    private func content(_ diff: GalaxyModel.Diff) -> some View {
        switch diff.content {
        case .noVersionBefore:
            note("Nessun diff: il Progetto non usa git, quindi manca la versione del file da cui è partita la Sessione.")
        case .loading:
            LoadingLabel("Leggo le modifiche…")
                .frame(maxWidth: .infinity)
        case .unreadable:
            note("Non riesco a leggere le modifiche della Sessione")
        case .file(nil):
            note("Nessuna differenza rispetto all'inizio della Sessione.")
        case let .file(file?):
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(file.hunks) { hunk in
                        hunkHeader(hunk, in: file, decision: diff.session.decisions[hunk.id])
                        ForEach(hunk.lines.indices, id: \.self) { index in
                            DiffLineRow(line: hunk.lines[index], isDecided: diff.session.decisions[hunk.id] != nil)
                        }
                    }
                }
            }
            .frame(maxHeight: 320)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The blocco's `@@` line, or what git says of a change without lines, with `+n −m` and its decision.
    private func hunkHeader(_ hunk: Hunk, in file: ChangedFile, decision: HunkDecision?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
            Text(verbatim: HunkHeaderRow.fallback(for: hunk, in: file))
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: "+\(hunk.added) −\(hunk.removed)")
                .foregroundStyle(Palette.textSecondary)
                .monospacedDigit()
            Text(HunkHeaderRow.state(of: decision))
                .foregroundStyle(HunkHeaderRow.stateColor(of: decision))
        }
        .font(Typography.mono(size: 11))
        .padding(.horizontal, Spacing.small)
        .padding(.top, Spacing.xSmall)
        .padding(.bottom, Spacing.xxSmall)
        .accessibilityElement(children: .combine)
    }

    private func note(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(Typography.body(size: 12))
            .foregroundStyle(Palette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
