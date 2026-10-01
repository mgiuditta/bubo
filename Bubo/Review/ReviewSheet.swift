import CoreServices
import os
import SwiftUI

/// The revisione of a Sessione, blocco by blocco: the files with a bar per blocco on the left, the continuous diff
/// on the right. `j`/`k` move between blocchi, `a` accepts, `x` rejects, `c` rejects with a note to the agent,
/// `⇧A` accepts the rest of the file; after a decision the cursor goes to the next undecided blocco.
/// `f` shows one blocco at a time, `s` before and after side by side; the same key goes back to the continuous diff.
/// `⌘↩` sends the rejected blocchi back to the agent or, with every blocco accepted, Fondi; conflicts are shown
/// before, the agent resolves them in the Sessione's worktree, and `⌘Z` undoes the merge for
/// `SessionStore.undoWindow`. The secondary menu merges only the accepted blocchi, after a confirmation.
///
/// The diff follows the files through FSEvents while the sheet is open, and runs git only then.
struct ReviewSheet: View {
    let sessionID: UUID
    let store: SessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var review = Review()
    @State private var isLoaded = false
    @State private var failed = false
    @State private var attempt = 0
    /// The blocco the keyboard acts on.
    @State private var cursor: String?
    /// The blocco whose note is being written.
    @State private var noting: String?
    @State private var note = ""
    @State private var mode = ReviewMode.continuous
    /// What Fondi would do now; `nil` until worked out, or without a branch of the Sessione's own.
    @State private var preview: MergePreview?
    @State private var message = ""
    @State private var strategy = MergeStrategy.squash
    @State private var isMerging = false
    /// Why the last Fondi or Annulla merge failed.
    @State private var mergeFailure: String?
    @State private var isConfirmingPartialMerge = false
    @FocusState private var isFocused: Bool
    @FocusState private var isEditingMessage: Bool

    private var session: Session? { store.sessions.first { $0.id == sessionID } }
    private var decisions: [String: HunkDecision] { session?.decisions ?? [:] }
    private var undoDeadline: Date? { store.undoDeadlines[sessionID] }

    /// Whether Fondi can merge now: every blocco accepted, no obstacle, the agent still.
    private var canMerge: Bool {
        review.canMerge(with: decisions) && preview != nil && preview?.obstacle == nil && session?.isRunning == false
            && session?.phase == .aperta && !isMerging
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            header
            if session?.workspace?.branch != nil {
                MergeBar(preview: preview, canMerge: review.canMerge(with: decisions), undoDeadline: undoDeadline,
                         failure: mergeFailure, resolvingBranch: session?.resolution?.branch, message: $message,
                         isEditingMessage: $isEditingMessage, undo: undo,
                         resolve: canResolve ? { resolveConflicts() } : nil)
            }
            if failed {
                ErrorNotice("Non riesco a leggere le modifiche della Sessione",
                            remedy: "Controlla che la copia della Sessione esista ancora, poi riprova.",
                            actionTitle: "Riprova") { attempt += 1 }
                Spacer()
            } else if !isLoaded {
                LoadingLabel("Leggo le modifiche…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if review.hunkIDs.isEmpty {
                Text("Nessuna modifica da rivedere.")
                    .font(Typography.body(size: 13))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if mode == .focus {
                focus
            } else {
                HStack(spacing: Spacing.small) {
                    ReviewFileList(review: review, decisions: decisions, conflicts: Set(preview?.conflicts ?? []),
                                   currentFile: cursor.flatMap(review.fileIndex(of:))) { cursor = $0 }
                        .frame(width: 240)
                    diff
                }
            }
        }
        .padding(Spacing.medium)
        .frame(minWidth: 960, minHeight: 640)
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(characters: CharacterSet(charactersIn: "jkaxcAfs"), phases: .down, action: handle)
        .onAppear {
            isFocused = true
            if let project = session?.project { strategy = .preferred(for: project) }
        }
        .onChange(of: session?.phase) { _, phase in
            // Annulla merge is over: the Sessione is archived, its worktree is going.
            if phase == .archiviata && mergeFailure == nil { dismiss() }
        }
        .onChange(of: review.canMerge(with: decisions), initial: true) { _, canMerge in
            if canMerge && message.isEmpty, let session { message = review.mergeMessage(for: session) }
        }
        // Also when the conflicts are resolved: the revisione then compares with the branch brought in.
        .task(id: FollowKey(attempt: attempt, base: session?.workspace?.base)) { await follow() }
    }

    /// What reading the changes again depends on: Riprova, and the base the revisione compares with.
    private struct FollowKey: Equatable {
        var attempt: Int
        var base: String?
    }

    /// Whether the agent can be asked to resolve the conflicts now: it is still, and Fondi is not merging.
    private var canResolve: Bool {
        session?.isRunning == false && session?.phase == .aperta && !isMerging
    }

    /// How many blocchi Fondi gli accettati would leave out.
    private var notAcceptedCount: Int {
        review.hunkIDs.count { decisions[$0] != .accepted }
    }

    /// Whether Fondi gli accettati can merge now: some blocchi accepted, not all, the agent still.
    private var canMergeAccepted: Bool {
        notAcceptedCount > 0 && notAcceptedCount < review.hunkIDs.count && session?.isRunning == false
            && session?.phase == .aperta && !isMerging
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
                Text("Revisione · \(session?.title ?? "")")
                    .font(Typography.display(size: 18))
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: summary)
                    .font(Typography.mono(size: 11))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: Spacing.small)
                Picker("Vista", selection: $mode.animation(Motion.isReduced ? nil : Motion.standard)) {
                    ForEach(ReviewMode.allCases, id: \.self) { Text($0.title) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Text("\(review.decidedCount(in: decisions))/\(review.hunkIDs.count) blocchi")
                    .font(Typography.mono(size: 11, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
                    .monospacedDigit()
                if review.canSendBack(with: decisions) || session?.workspace?.branch == nil {
                    Button("Rimanda all'agente", action: sendBack)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(!review.canSendBack(with: decisions) || session?.isRunning != false)
                        .help("I blocchi rifiutati tornano all'agente con le note, come nuovo turno della Sessione")
                } else {
                    Picker("Merge", selection: $strategy) {
                        ForEach(MergeStrategy.allCases, id: \.self) { Text($0.title) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .onChange(of: strategy) {
                        if let project = session?.project { strategy.makePreferred(for: project) }
                    }
                    .help("Come il Progetto fonde le Sessioni: squash in un commit, o merge commit")
                    Button("Fondi") { merge() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(!canMerge)
                        .help("Fonde le modifiche accettate nel branch del checkout con un commit locale, senza push")
                }
                if session?.workspace?.branch != nil {
                    Menu("Altre azioni", systemImage: "ellipsis.circle") {
                        Button("Fondi gli accettati e scarta il resto…") { isConfirmingPartialMerge = true }
                            .disabled(!canMergeAccepted)
                    }
                    .labelStyle(.iconOnly)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .confirmationDialog("Fondere solo i blocchi accettati?", isPresented: $isConfirmingPartialMerge) {
                        Button("Fondi gli accettati", role: .destructive) { merge(discardingRest: true) }
                    } message: {
                        Text("I blocchi non accettati restano fuori dal merge e se ne vanno con la Sessione. Subito dopo puoi ancora annullare il merge.")
                    }
                }
                Button("Chiudi") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(noting != nil)
            }
            Text("j k blocco · a accetta · x rifiuta · c nota all'agente · ⇧A accetta il file · f focus · s affiancato · ⌘↩ fondi o rimanda all'agente")
                .font(Typography.mono(size: 10.5))
                .foregroundStyle(Palette.textFaint)
        }
    }

    /// Branch, files, lines added and removed.
    private var summary: String {
        let hunks = review.files.flatMap(\.hunks)
        let parts = [session?.workspace?.branch,
                     String(localized: "\(review.files.count) file"),
                     "+\(hunks.reduce(0) { $0 + $1.added }) −\(hunks.reduce(0) { $0 + $1.removed })"]
        return parts.compactMap(\.self).joined(separator: " · ")
    }

    private var diff: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(mode == .sideBySide ? review.sideBySideRows : review.rows) { row in
                        rowView(row)
                    }
                }
                .padding(.trailing, Spacing.xSmall)
            }
            .onChange(of: cursor) { scroll(proxy) }
            .onChange(of: mode, initial: true) { scroll(proxy) }
        }
    }

    /// Brings the header of the cursor's blocco into view.
    private func scroll(_ proxy: ScrollViewProxy) {
        guard let cursor,
              let row = mode == .sideBySide ? review.sideBySideRow(of: cursor) : review.row(of: cursor) else { return }
        proxy.scrollTo(row)
    }

    /// One blocco at a time, large: where it is, its header and lines, Rifiuta, Nota, Accetta, and every blocco under.
    @ViewBuilder
    private var focus: some View {
        if let id = cursor ?? review.hunkIDs.first, let place = review.hunk(id) {
            let (file, hunk) = place
            VStack(spacing: Spacing.small) {
                Text("\(file.path) · blocco \((file.hunks.firstIndex(of: hunk) ?? 0) + 1) di \(file.hunks.count) nel file")
                    .font(Typography.mono(size: 12))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                VStack(alignment: .leading, spacing: 0) {
                    hunkHeader(file: file, hunk: hunk, showsButtons: false)
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(hunk.lines.indices, id: \.self) { index in
                                DiffLineRow(line: hunk.lines[index], isDecided: decisions[id] != nil, size: 13.5)
                            }
                        }
                    }
                }
                .frame(maxWidth: 900, maxHeight: .infinity)
                .id(id)
                .transition(.opacity)
                HStack(spacing: Spacing.small) {
                    Button("Rifiuta") { decide(.rejected(note: nil), on: id) }
                        .tint(Palette.danger)
                    Button("Nota") { startNote(on: id) }
                    Button("Accetta") { decide(.accepted, on: id) }
                        .tint(Palette.success)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(noting != nil)
                HunkStrip(ids: review.hunkIDs, decisions: decisions, current: id) { cursor = $0 }
                    .frame(maxWidth: 900)
            }
            .frame(maxWidth: .infinity)
            .animation(Motion.isReduced ? nil : Motion.standard, value: id)
        }
    }

    @ViewBuilder
    private func rowView(_ row: Review.Row) -> some View {
        switch row.kind {
        case let .file(index):
            let file = review.files[index]
            Text(verbatim: file.oldPath.map { "\($0) → \(file.path)" } ?? file.path)
                .font(Typography.mono(size: 11.5, weight: .medium))
                .foregroundStyle(Palette.textPrimary)
                .padding(.top, Spacing.small)
                .padding(.bottom, Spacing.xxSmall)
                .accessibilityAddTraits(.isHeader)
        case let .hunk(fileIndex, hunkIndex):
            let file = review.files[fileIndex]
            hunkHeader(file: file, hunk: file.hunks[hunkIndex])
        case let .line(fileIndex, hunkIndex, lineIndex):
            let hunk = review.files[fileIndex].hunks[hunkIndex]
            DiffLineRow(line: hunk.lines[lineIndex], isDecided: decisions[hunk.id] != nil)
        case let .pair(fileIndex, hunkIndex, pairIndex):
            let hunk = review.files[fileIndex].hunks[hunkIndex]
            SideBySideLineRow(pair: hunk.pairs[pairIndex], isDecided: decisions[hunk.id] != nil)
        }
    }

    private func hunkHeader(file: ChangedFile, hunk: Hunk, showsButtons: Bool = true) -> some View {
        HunkHeaderRow(file: file, hunk: hunk,
                      position: (review.hunkIDs.firstIndex(of: hunk.id) ?? 0) + 1, count: review.hunkIDs.count,
                      reason: session?.reason(for: hunk, inFileAt: file.path), decision: decisions[hunk.id],
                      isCurrent: cursor == hunk.id, isNoting: noting == hunk.id, showsButtons: showsButtons,
                      note: $note) { decision in
            cursor = hunk.id
            decide(decision, on: hunk.id)
        } saveNote: {
            saveNote(on: hunk.id)
        } cancelNote: {
            noting = nil
            isFocused = true
        }
        .onTapGesture { cursor = hunk.id }
    }

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        guard noting == nil, !isEditingMessage, session?.phase == .aperta, let current = cursor ?? review.hunkIDs.first
        else { return .ignored }
        switch press.characters {
        case "j": cursor = review.hunk(movingBy: 1, from: current)
        case "k": cursor = review.hunk(movingBy: -1, from: current)
        case "a": decide(.accepted, on: current)
        case "x": decide(.rejected(note: nil), on: current)
        case "c": startNote(on: current)
        case "A": acceptFile(of: current)
        case "f": show(mode == .focus ? .continuous : .focus)
        case "s": show(mode == .sideBySide ? .continuous : .sideBySide)
        default: return .ignored
        }
        return .handled
    }

    private func show(_ newMode: ReviewMode) {
        withAnimation(Motion.isReduced ? nil : Motion.standard) { mode = newMode }
    }

    /// Opens the note to the agent on the blocco `id`, with the note it already has.
    private func startNote(on id: String) {
        cursor = id
        if case let .rejected(saved) = decisions[id] { note = saved ?? "" } else { note = "" }
        noting = id
    }

    /// Records `decision` on the blocco `id`, or takes it back when it was already the decision; then moves the
    /// cursor to the next undecided blocco.
    private func decide(_ decision: HunkDecision, on id: String) {
        let isUndoing = decisions[id] == decision
        store.decide(isUndoing ? nil : decision, on: [id], in: sessionID)
        cursor = isUndoing ? id : review.nextUndecided(after: id, in: decisions)
    }

    private func saveNote(on id: String) {
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        store.decide(.rejected(note: text.isEmpty ? nil : text), on: [id], in: sessionID)
        noting = nil
        isFocused = true
        cursor = review.nextUndecided(after: id, in: decisions)
    }

    /// Accepts the undecided blocchi of the file of `id`.
    private func acceptFile(of id: String) {
        guard let index = review.fileIndex(of: id) else { return }
        let undecided = review.files[index].hunks.map(\.id).filter { decisions[$0] == nil }
        store.decide(.accepted, on: undecided, in: sessionID)
        cursor = review.nextUndecided(after: id, in: decisions)
    }

    private func sendBack() {
        store.sendBack(review.feedback(for: decisions), to: sessionID, keepingAcceptedAmong: review.hunkIDs)
        dismiss()
    }

    /// Fondi, with the message as the user left it; only the accepted blocchi when `discardingRest`.
    private func merge(discardingRest: Bool = false) {
        let text = discardingRest ? "" : message.trimmingCharacters(in: .whitespacesAndNewlines)
        let commitMessage = text.isEmpty ? session.map(review.mergeMessage(for:)) ?? "" : text
        isMerging = true
        mergeFailure = nil
        isEditingMessage = false
        isFocused = true
        Task {
            defer { isMerging = false }
            do {
                try await store.merge(sessionID, message: commitMessage, strategy: strategy,
                                      discardingRest: discardingRest)
            } catch {
                Logger.sessions.error("Fondi failed: \(String(describing: error), privacy: .private)")
                mergeFailure = Self.explanation(of: error)
                await refreshPreview()
            }
        }
    }

    /// Risolvi con l'agente: the branch of the checkout comes into the Sessione's worktree, the agent resolves there.
    private func resolveConflicts() {
        mergeFailure = nil
        Task {
            do {
                try await store.resolveConflicts(sessionID)
            } catch {
                Logger.sessions.error("Conflicts not brought in: \(String(describing: error), privacy: .private)")
                mergeFailure = Self.explanation(of: error)
            }
        }
    }

    private func undo() {
        Task {
            do {
                try await store.undoMerge(sessionID)
                await refreshPreview()
            } catch {
                mergeFailure = Self.explanation(of: error)
            }
        }
    }

    /// What to tell the user about `error` from Fondi or Annulla merge.
    private static func explanation(of error: any Error) -> String {
        switch error {
        case let error as MergeError: error.localizedDescription
        case let WorktreeError.git(message):
            String(localized: "git si è fermato: \(message.trimmingCharacters(in: .whitespacesAndNewlines))")
        default: error.localizedDescription
        }
    }

    /// Works out again what Fondi would do now.
    private func refreshPreview() async {
        do {
            preview = try await store.mergePreview(of: sessionID)
        } catch is CancellationError {
        } catch {
            preview = nil
            mergeFailure = Self.explanation(of: error)
        }
    }

    /// Reads the changes, then again after every write in the Sessione's folder, until the sheet closes.
    private func follow() async {
        guard let folder = session?.workspace?.folder else { return }
        await refresh()
        let since = FSEventStreamEventId(kFSEventStreamEventIdSinceNow)
        for await batch in FileEvents.batches(under: folder.path, since: since, latency: 0.05) {
            // git's own bookkeeping does not change the diff; a commit changes no file of the folder.
            guard batch.needsRescan || batch.paths.contains(where: { !$0.contains("/.git/") }) else { continue }
            await refresh()
        }
    }

    private func refresh() async {
        do {
            review = Review(files: try await store.changes(of: sessionID))
            failed = false
            if session?.phase == .aperta { await refreshPreview() }
            if cursor.flatMap(review.row(of:)) == nil {
                cursor = review.hunkIDs.first { decisions[$0] == nil } ?? review.hunkIDs.first
            }
        } catch is CancellationError {
            return
        } catch {
            Logger.sessions.error("Revisione not read: \(String(describing: error), privacy: .private)")
            failed = true
        }
        isLoaded = true
    }
}
