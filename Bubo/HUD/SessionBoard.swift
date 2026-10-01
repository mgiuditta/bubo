import SwiftUI

/// The Board Vista of the HUD: Da iniziare with the Bozze, then the Sessioni in five columns derived by
/// `BoardColumn`, always shown in the same order, also when empty; Attende te first, the longest wait on top. The
/// Sessioni's cards do not drag: the Fase changes only with an action. The only drag is a Bozza onto the Sessioni,
/// which starts it like ↩ and Avvia. Chips filter by Progetto.
struct SessionBoard: View {
    let store: SessionStore
    var gate = TrustGate()
    @Environment(HUDPresenter.self) private var hud
    /// The Progetto whose Sessioni and Bozze are shown; `nil` for all of them.
    @State private var project: URL?
    /// Whether Fusa shows all its cards instead of the first two.
    @State private var isFusaUnfolded = false
    /// The Bozza waiting for the trust dialog of its Progetto before it starts.
    @State private var trusting: Draft?
    /// The column a Bozza is being dragged over.
    @State private var dropTarget: BoardColumn?
    /// Why the Sessione of a Bozza dropped on a column is not there, for a few seconds.
    @State private var notice: LocalizedStringResource?

    /// How many cards Fusa shows before folding the others.
    private static let fusaFold = 2

    private var columns: [(column: BoardColumn, sessions: [Session])] {
        let shown = project.map { project in store.sessions.filter { $0.project == project } } ?? store.sessions
        return BoardColumn.columns(of: shown, at: .now)
    }

    /// The Bozze shown in Da iniziare, oldest first.
    private var drafts: [Draft] {
        project.map { project in store.drafts.drafts.filter { $0.project == project } } ?? store.drafts.drafts
    }

    /// The Progetti of the Sessioni, then those with only Bozze.
    private var projects: [URL] {
        let projects = store.projects
        var seen = Set(projects)
        return projects + store.drafts.drafts.reversed().map(\.project).filter { seen.insert($0).inserted }
    }

    var body: some View {
        let columns = columns
        let projects = projects
        VStack(alignment: .leading, spacing: Spacing.small) {
            if projects.count > 1 { projectChips(projects) }
            if let notice {
                Text(notice)
                    .font(Typography.body(size: 12))
                    .foregroundStyle(Palette.textSecondary)
            }
            ScrollView(.horizontal) {
                GlassEffectContainer(spacing: Spacing.xSmall) {
                    HStack(alignment: .top, spacing: Spacing.xSmall) {
                        draftColumn
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
        .sheet(item: $trusting) { draft in
            TrustSheet(folder: draft.project, activations: RepoActivations(folder: draft.project),
                       start: { _ in store.start(draft) }, gate: gate)
        }
        .task(id: notice == nil) {
            guard notice != nil else { return }
            try? await Task.sleep(for: .seconds(6))
            notice = nil
        }
    }

    /// Avvia: starts `draft`, after the trust dialog when its Progetto is not trusted. Dropped on `column`, other
    /// than Lavora or Attende te, a notice says where the Sessione goes.
    private func start(_ draft: Draft, droppedOn column: BoardColumn? = nil) {
        guard draft.unreachableReason == nil else { return }
        if let column, column != .lavora, column != .attendeTe {
            let notice: LocalizedStringResource = "Una Sessione parte sempre in Lavora: la colonna segue quello che fa."
            self.notice = notice
            AccessibilityNotification.Announcement(String(localized: notice)).post()
        }
        if gate.isTrusted(draft.project) {
            store.start(draft)
        } else {
            trusting = draft
        }
    }

    private func projectChips(_ projects: [URL]) -> some View {
        HStack(spacing: Spacing.xxSmall) {
            chip(Text("Tutti i Progetti"), for: nil)
            ForEach(projects, id: \.self) { project in
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

    private func columnHeader(_ title: Text, count: Int, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline) {
            title
                .font(Typography.body(size: 12, weight: .semibold))
                .foregroundStyle(color)
            Spacer()
            Text(count, format: .number)
                .font(Typography.mono(size: 11))
                .foregroundStyle(Palette.textFaint)
        }
        .padding(.horizontal, Spacing.xxSmall)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// Da iniziare: only Bozze, never Sessioni.
    private var draftColumn: some View {
        let drafts = drafts
        return VStack(alignment: .leading, spacing: Spacing.xSmall) {
            columnHeader(Text("Da iniziare"), count: drafts.count, color: Palette.textPrimary)
            Button("Nuova Bozza", systemImage: "plus") { hud.createDraft() }
                .buttonStyle(.plain)
                .font(Typography.body(size: 12))
                .foregroundStyle(Palette.textSecondary)
                .padding(.horizontal, Spacing.xxSmall)
                .help("Nuova Bozza (⌥⌘N)")
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.xSmall) {
                    ForEach(drafts) { draft in
                        draftCard(draft)
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

    /// A Bozza: ↩ with the card focused, Avvia, or a drag onto the Sessioni starts it.
    private func draftCard(_ draft: Draft) -> some View {
        let reason = draft.unreachableReason
        return VStack(alignment: .leading, spacing: Spacing.xxSmall) {
            Text("Bozza")
                .font(Typography.mono(size: 10))
                .foregroundStyle(Palette.textFaint)
            Text(verbatim: draft.title)
                .font(Typography.body(size: 13, weight: .semibold))
                .lineLimit(2)
            Text(verbatim: draft.project.lastPathComponent)
                .font(Typography.mono(size: 11))
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
            if let reason {
                Text(verbatim: reason)
                    .font(Typography.body(size: 12))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(3)
            }
            Button("Avvia ↩") { start(draft) }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(reason != nil)
                // VoiceOver says the action, not the key.
                .accessibilityLabel("Avvia")
                .padding(.top, Spacing.xxSmall)
        }
        .padding(Spacing.xSmall)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.ink.opacity(0.6), in: .rect(cornerRadius: CornerRadius.medium))
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.medium).strokeBorder(Palette.line)
        }
        .focusable()
        .onKeyPress(.return) {
            start(draft)
            return .handled
        }
        .draggable(draft.id.uuidString)
        .contextMenu {
            Button("Elimina Bozza", role: .destructive) { store.drafts.remove(draft.id) }
        }
        .accessibilityElement(children: .contain)
    }

    private func columnView(_ column: BoardColumn, sessions: [Session]) -> some View {
        let isFolded = column == .fusa && !isFusaUnfolded && sessions.count > Self.fusaFold
        let shown = isFolded ? Array(sessions.prefix(Self.fusaFold)) : sessions
        return VStack(alignment: .leading, spacing: Spacing.xSmall) {
            columnHeader(Text(column.title), count: sessions.count,
                         color: column == .attendeTe ? Palette.attention : Palette.textPrimary)
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
        .overlay {
            if dropTarget == column {
                RoundedRectangle(cornerRadius: CornerRadius.large).strokeBorder(Palette.accent)
            }
        }
        // Only a Bozza starts here: any other text dropped is not one of their ids.
        .dropDestination(for: String.self) { ids, _ in
            guard let draft = store.drafts.drafts.first(where: { ids.contains($0.id.uuidString) }) else { return false }
            start(draft, droppedOn: column)
            return true
        } isTargeted: { isTargeted in
            if isTargeted { dropTarget = column } else if dropTarget == column { dropTarget = nil }
        }
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
    let drafts = DraftStore()
    drafts.add(Draft(title: "Esporta in CSV", text: "Dal menu File, con le colonne visibili", project: folder))
    return SessionBoard(store: SessionStore(file: file, worktrees: WorktreeManager(root: folder), drafts: drafts) {
        throw CancellationError()
    })
    .padding()
    .frame(height: 600)
    .background(Palette.ink)
    .environment(HUDPresenter())
}
