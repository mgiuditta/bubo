import os
import SwiftUI

/// ⌘I: the open GitHub issues of a Progetto, read with the user's `gh`; ↩ starts a Sessione on the selected one, ⌥↩
/// saves it as a Bozza, and both open the Bozza or the Sessione it already has (spec 16).
///
/// The issue's text reaches the agent as material written by others, never as an instruction. In a folder that is
/// not trusted, the trust dialog comes first (#266).
struct IssuePicker: View {
    let store: SessionStore
    var cli = GitHubCLI()
    var gate = TrustGate()
    @Environment(HUDPresenter.self) private var hud
    @Environment(\.dismiss) private var dismiss
    @State private var project: URL?
    @State private var repository: GitHubRepository?
    @State private var search = ""
    @State private var issues: [GitHubIssue] = []
    @State private var selection: GitHubIssue.ID?
    @State private var isLoading = false
    /// Why the issues or the selected one could not be read, as `gh` or Bubo says it.
    @State private var failure: String?
    /// The issue being read before its Sessione starts.
    @State private var reading: GitHubIssue.ID?
    /// Reads the issue: Annulla stops it, and no Sessione starts.
    @State private var readingTask: Task<Void, Never>?
    /// The closed Sessione of the selected issue, while Riprendi or Nuova Sessione is asked.
    @State private var closed: Session?
    @State private var isAskingAboutClosed = false
    /// What starts once the trust dialog is answered.
    @State private var pending: Launch?
    @State private var isChoosingFolder = false
    @FocusState private var isSearchFocused: Bool

    /// What ↩ starts: a new Sessione on an issue, or Riprendi on an Archiviata one; with the issue already read.
    private struct Launch {
        var number: Int
        var context: GitHubIssueContext
        var reopening: Session.ID?
    }

    /// What the issues are read for: the Progetto and the search.
    private struct LoadKey: Equatable {
        var project: URL?
        var search: String
    }

    var body: some View {
        if let pending, let project {
            TrustSheet(folder: project, activations: RepoActivations(folder: project),
                       start: { _ in launch(pending) }, gate: gate)
        } else {
            picker
        }
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            HStack {
                Text("Progetto")
                    .foregroundStyle(Palette.textSecondary)
                Text(verbatim: project?.lastPathComponent ?? "")
                    .help(project?.path ?? "")
                Button(project == nil ? "Scegli cartella…" : "Cambia…") { isChoosingFolder = true }
                Spacer()
                if let repository {
                    Text(verbatim: "\(repository.owner)/\(repository.name)")
                        .font(Typography.mono(size: 11))
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            TextField("Cerca", text: $search, prompt: Text("Cerca nelle issue aperte"))
                .textFieldStyle(.roundedBorder)
                .focused($isSearchFocused)
                .onKeyPress(.downArrow) { moveSelection(by: 1) }
                .onKeyPress(.upArrow) { moveSelection(by: -1) }
            content
                .frame(maxWidth: .infinity, minHeight: 280, maxHeight: .infinity)
            HStack {
                if reading != nil { LoadingLabel("Leggo l'issue…") }
                Spacer()
                Button("Annulla", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                if !selectedMatch.isOpen {
                    Button("Salva come Bozza", action: saveAsDraft)
                        .keyboardShortcut(.return, modifiers: .option)
                        .disabled(selection == nil || reading != nil)
                        .help("Salva l'issue in Da iniziare senza avviarla (⌥↩)")
                }
                Button(goTitle, action: go)
                    .keyboardShortcut(.defaultAction)
                    .disabled(selection == nil || reading != nil)
            }
        }
        .padding(Spacing.medium)
        .frame(width: 560, height: 460)
        .onAppear {
            project = project ?? store.projects.first
            isSearchFocused = true
        }
        .task(id: LoadKey(project: project, search: search)) { await load() }
        .onChange(of: project) {
            repository = nil
            issues = []
            failure = nil
        }
        .onDisappear { readingTask?.cancel() }
        .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
            if case let .success(folder) = result { project = folder }
        }
        .confirmationDialog(closedTitle, isPresented: $isAskingAboutClosed, presenting: closed) { session in
            if session.phase == .archiviata {
                Button("Riprendi") { read(reopening: session.id) }
            }
            Button("Nuova Sessione") { read(reopening: nil) }
        } message: { session in
            Text(session.phase == .archiviata
                 ? "Riprendi la riapre sul suo branch. Nuova Sessione parte da capo su un branch nuovo."
                 : "La Sessione è appena stata fusa. Nuova Sessione parte da capo su un branch nuovo.")
        }
    }

    @ViewBuilder
    private var content: some View {
        if project == nil {
            message("Scegli la cartella di un Progetto con un remoto su GitHub.")
        } else if let failure {
            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                Label {
                    Text(verbatim: failure)
                        .textSelection(.enabled)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Palette.danger)
                }
                Button("Riprova") { Task { await load() } }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if issues.isEmpty {
            if isLoading {
                LoadingLabel("Leggo le issue…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                message(search.isEmpty ? "Nessuna issue aperta." : "Nessuna issue aperta corrisponde alla ricerca.")
            }
        } else {
            List(issues, selection: $selection) { issue in
                IssueRow(issue: issue, match: match(of: issue.number))
                    .tag(issue.id)
            }
            .accessibilityLabel("Issue aperte")
            .contextMenu(forSelectionType: GitHubIssue.ID.self) { _ in
            } primaryAction: { _ in
                go()
            }
        }
    }

    private func message(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .foregroundStyle(Palette.textSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var closedTitle: Text {
        guard let closed, let label = closed.issue?.label else { return Text(verbatim: "") }
        return Text("L'issue \(label) ha già una Sessione: «\(closed.title)».")
    }

    private func match(of number: Int) -> IssueLink.Match {
        guard let project else { return .none }
        return IssueLink.github(number).match(in: store.sessions, drafts: store.drafts.drafts, on: project)
    }

    /// ↩'s button: what it does with the selected issue.
    private var goTitle: LocalizedStringKey {
        // Statements, not a switch expression: the String Catalog takes only the first branch of one.
        switch selectedMatch {
        case .draft: return "Apri la Bozza"
        case .open: return "Apri la Sessione"
        case .none, .closed: return "Avvia"
        }
    }

    private var selectedMatch: IssueLink.Match {
        selection.map(match(of:)) ?? .none
    }

    private func moveSelection(by step: Int) -> KeyPress.Result {
        guard !issues.isEmpty else { return .ignored }
        let index = selection.flatMap { selected in issues.firstIndex { $0.id == selected } } ?? -step
        selection = issues[min(max(index + step, 0), issues.count - 1)].id
        return .handled
    }

    /// Reads the open issues of the Progetto, those matching the search once the user stops typing.
    private func load() async {
        guard let project else { return }
        if !search.isEmpty {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let repository = try await cli.repository(of: project)
            self.repository = repository
            let issues = try await cli.openIssues(of: repository, matching: search)
            guard !Task.isCancelled else { return }
            failure = nil
            self.issues = issues
            if !issues.contains(where: { $0.id == selection }) { selection = issues.first?.id }
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled else { return }
            Logger.sessions.error("Issues not read: \(String(describing: error), privacy: .private)")
            issues = []
            failure = error.localizedDescription
        }
    }

    /// ↩: opens the Bozza or the Sessione the issue already has; asks about one Archiviata or Fusa; else starts a new one.
    private func go() {
        guard let selection, reading == nil else { return }
        switch match(of: selection) {
        case .draft:
            dismiss()
            hud.showDrafts()
        case .open:
            dismiss()
            hud.show()
        case let .closed(session):
            closed = session
            isAskingAboutClosed = true
        case .none:
            read(reopening: nil)
        }
    }

    /// ⌥↩: saves the selected issue as a Bozza in Da iniziare, with only its title: the issue is read at Avvia. No
    /// doppioni: with a Bozza already there, the Board shows it.
    private func saveAsDraft() {
        guard let project, let issue = issues.first(where: { $0.id == selection }), reading == nil else { return }
        store.addDraft(Draft(title: issue.title, text: "", project: project, issue: .github(issue.number)))
        dismiss()
        hud.showDrafts()
    }

    /// Reads the selected issue with `gh issue view`, then starts its Sessione, or reopens `reopening`.
    private func read(reopening: Session.ID?) {
        guard let number = selection, let repository, reading == nil else { return }
        reading = number
        readingTask = Task {
            defer { reading = nil }
            do {
                let context = try await cli.context(ofIssue: number, in: repository)
                guard !Task.isCancelled else { return }
                let launch = Launch(number: number, context: context, reopening: reopening)
                if let project, gate.isTrusted(project) {
                    self.launch(launch)
                    dismiss()
                } else {
                    pending = launch
                }
            } catch {
                guard !Task.isCancelled else { return }
                Logger.sessions.error("Issue not read: \(String(describing: error), privacy: .private)")
                failure = error.localizedDescription
            }
        }
    }

    /// Starts the Sessione of `launch`; the trust dialog closes the sheet on its own.
    private func launch(_ launch: Launch) {
        guard let project else { return }
        if let id = launch.reopening {
            do {
                try store.reopen(id, prompt: launch.context.prompt(number: launch.number))
            } catch {
                // A Sessione from an issue never works on the checkout: only one from elsewhere could get here.
                Logger.sessions.error("Sessione not reopened: \(String(describing: error), privacy: .public)")
            }
        } else {
            store.start(issue: launch.number, launch.context, in: project)
        }
    }
}

private extension IssueLink.Match {
    /// Whether ↩ opens a Bozza or a Sessione instead of starting one.
    var isOpen: Bool {
        switch self {
        case .draft, .open: true
        case .none, .closed: false
        }
    }
}
