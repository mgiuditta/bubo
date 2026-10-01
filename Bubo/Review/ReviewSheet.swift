import CoreServices
import os
import SwiftUI

/// The revisione of a Sessione, blocco by blocco: the files with a bar per blocco on the left, the continuous diff
/// on the right. `j`/`k` move between blocchi, `a` accepts, `x` rejects, `c` rejects with a note to the agent,
/// `⇧A` accepts the rest of the file; after a decision the cursor goes to the next undecided blocco.
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
    @FocusState private var isFocused: Bool

    private var session: Session? { store.sessions.first { $0.id == sessionID } }
    private var decisions: [String: HunkDecision] { session?.decisions ?? [:] }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            header
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
            } else {
                HStack(spacing: Spacing.small) {
                    ReviewFileList(review: review, decisions: decisions,
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
        .onKeyPress(characters: CharacterSet(charactersIn: "jkaxcA"), phases: .down, action: handle)
        .onAppear { isFocused = true }
        .task(id: attempt) { await follow() }
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
                Text("\(review.decidedCount(in: decisions))/\(review.hunkIDs.count) blocchi")
                    .font(Typography.mono(size: 11, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
                    .monospacedDigit()
                Button("Rimanda all'agente", action: sendBack)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!review.canSendBack(with: decisions) || session?.isRunning != false)
                    .help("I blocchi rifiutati tornano all'agente con le note, come nuovo turno della Sessione")
                Button("Chiudi") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(noting != nil)
            }
            Text("j k blocco · a accetta · x rifiuta · c nota all'agente · ⇧A accetta il file · ⌘↩ rimanda all'agente")
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
                    ForEach(review.rows) { row in
                        rowView(row)
                    }
                }
                .padding(.trailing, Spacing.xSmall)
            }
            .onChange(of: cursor) {
                guard let cursor, let row = review.row(of: cursor) else { return }
                proxy.scrollTo(row)
            }
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
            let hunk = file.hunks[hunkIndex]
            HunkHeaderRow(file: file, hunk: hunk,
                          position: (review.hunkIDs.firstIndex(of: hunk.id) ?? 0) + 1, count: review.hunkIDs.count,
                          reason: session?.reason(for: hunk, inFileAt: file.path), decision: decisions[hunk.id],
                          isCurrent: cursor == hunk.id, isNoting: noting == hunk.id, note: $note) { decision in
                cursor = hunk.id
                decide(decision, on: hunk.id)
            } saveNote: {
                saveNote(on: hunk.id)
            } cancelNote: {
                noting = nil
                isFocused = true
            }
            .onTapGesture { cursor = hunk.id }
        case let .line(fileIndex, hunkIndex, lineIndex):
            let hunk = review.files[fileIndex].hunks[hunkIndex]
            DiffLineRow(line: hunk.lines[lineIndex], isDecided: decisions[hunk.id] != nil)
        }
    }

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        guard noting == nil, let current = cursor ?? review.hunkIDs.first else { return .ignored }
        switch press.characters {
        case "j": cursor = review.hunk(movingBy: 1, from: current)
        case "k": cursor = review.hunk(movingBy: -1, from: current)
        case "a": decide(.accepted, on: current)
        case "x": decide(.rejected(note: nil), on: current)
        case "c":
            cursor = current
            if case let .rejected(saved) = decisions[current] { note = saved ?? "" } else { note = "" }
            noting = current
        case "A": acceptFile(of: current)
        default: return .ignored
        }
        return .handled
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
