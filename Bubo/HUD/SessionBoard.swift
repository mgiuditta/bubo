import SwiftUI

/// The Board Vista of the HUD: the Sessioni in five columns derived by `BoardColumn`, always shown in the same
/// order, also when empty; Attende te first, the longest wait on top. The cards do not drag: the Fase changes only
/// with an action. Chips filter by Progetto.
struct SessionBoard: View {
    let store: SessionStore
    /// The Progetto whose Sessioni are shown; `nil` for all of them.
    @State private var project: URL?
    /// Whether Fusa shows all its cards instead of the first two.
    @State private var isFusaUnfolded = false

    /// How many cards Fusa shows before folding the others.
    private static let fusaFold = 2

    private var columns: [(column: BoardColumn, sessions: [Session])] {
        let shown = project.map { project in store.sessions.filter { $0.project == project } } ?? store.sessions
        return BoardColumn.columns(of: shown, at: .now)
    }

    var body: some View {
        let columns = columns
        VStack(alignment: .leading, spacing: Spacing.small) {
            if store.projects.count > 1 { projectChips }
            ScrollView(.horizontal) {
                GlassEffectContainer(spacing: Spacing.xSmall) {
                    HStack(alignment: .top, spacing: Spacing.xSmall) {
                        ForEach(columns, id: \.column) { column, sessions in
                            columnView(column, sessions: sessions)
                        }
                    }
                }
            }
            .scrollIndicators(.automatic)
        }
        // Reduce Motion: the cards jump to their new column.
        .animation(Motion.isReduced ? nil : Motion.emphasized, value: columns.map { $0.sessions.map(\.id) })
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sessioni")
    }

    private var projectChips: some View {
        HStack(spacing: Spacing.xxSmall) {
            chip(Text("Tutti i Progetti"), for: nil)
            ForEach(store.projects, id: \.self) { project in
                chip(Text(verbatim: project.lastPathComponent), for: project)
            }
        }
        .controlSize(.small)
    }

    private func chip(_ title: Text, for project: URL?) -> some View {
        let isSelected = self.project == project
        return Button { self.project = project } label: { title }
            .buttonStyle(.bordered)
            .tint(isSelected ? Palette.accent : nil)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func columnView(_ column: BoardColumn, sessions: [Session]) -> some View {
        let isFolded = column == .fusa && !isFusaUnfolded && sessions.count > Self.fusaFold
        let shown = isFolded ? Array(sessions.prefix(Self.fusaFold)) : sessions
        return VStack(alignment: .leading, spacing: Spacing.xSmall) {
            HStack(alignment: .firstTextBaseline) {
                Text(column.title)
                    .font(Typography.body(size: 12, weight: .semibold))
                    .foregroundStyle(column == .attendeTe ? Palette.attention : Palette.textPrimary)
                Spacer()
                Text(sessions.count, format: .number)
                    .font(Typography.mono(size: 11))
                    .foregroundStyle(Palette.textFaint)
            }
            .padding(.horizontal, Spacing.xxSmall)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.xSmall) {
                    ForEach(shown) { session in
                        card(session)
                    }
                    if isFolded {
                        Button("… \(sessions.count - shown.count) altre") { isFusaUnfolded = true }
                            .buttonStyle(.plain)
                            .font(Typography.body(size: 12))
                            .foregroundStyle(Palette.textSecondary)
                            .padding(Spacing.xxSmall)
                    }
                }
            }
            .scrollIndicators(.never)
        }
        .padding(Spacing.xSmall)
        .frame(width: 260, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
        .glassEffect(.regular, in: .rect(cornerRadius: CornerRadius.large))
        .accessibilityElement(children: .contain)
    }

    private func card(_ session: Session) -> some View {
        let border = switch session.activity {
        case .attende where session.phase == .aperta: Palette.attention.opacity(0.45)
        case .errore where session.phase == .aperta: Palette.danger.opacity(0.45)
        default: Palette.line
        }
        return SessionRow(session: session, store: store, isOnBoard: true)
            .background(Palette.ink.opacity(0.6), in: .rect(cornerRadius: CornerRadius.medium))
            .overlay {
                RoundedRectangle(cornerRadius: CornerRadius.medium).strokeBorder(border)
            }
    }
}

#Preview {
    let folder = FileManager.default.temporaryDirectory
    let file = folder.appending(path: "SessionBoardPreview.json")
    var merged = Session(id: UUID(), title: "Icona del Dock", project: folder, activity: .ferma,
                         activitySince: .now.addingTimeInterval(-7_200), summary: "Fusa in main")
    merged.phase = .archiviata
    merged.mergedAt = .now.addingTimeInterval(-3_600)
    try? JSONEncoder().encode([
        merged,
        Session(id: UUID(), title: "Refactor del router", project: folder,
                workspace: Workspace(folder: folder, branch: "bubo/refactor-del-router"), activity: .lavora,
                activitySince: .now.addingTimeInterval(-720), summary: "Sposta la Scala in un tipo a sé"),
        Session(id: UUID(), title: "Pagina prezzi", project: folder,
                workspace: Workspace(folder: folder, branch: "bubo/pagina-prezzi"), activity: .ferma,
                activitySince: .now.addingTimeInterval(-2_400), summary: "Finito: tabella e FAQ"),
        Session(id: UUID(), title: "Login con passkey", project: folder,
                workspace: Workspace(folder: folder, branch: "bubo/login-con-passkey"), activity: .attende,
                activitySince: .now.addingTimeInterval(-240), summary: "Vuole migrare il Portachiavi"),
        Session(id: UUID(), title: "Crash all'avvio", project: folder, activity: .errore,
                activitySince: .now.addingTimeInterval(-1_560), failure: "Manca la destinazione x86_64"),
    ]).write(to: file)
    return SessionBoard(store: SessionStore(file: file, worktrees: WorktreeManager(root: folder)) {
        throw CancellationError()
    })
    .padding()
    .frame(height: 600)
    .background(Palette.ink)
}
