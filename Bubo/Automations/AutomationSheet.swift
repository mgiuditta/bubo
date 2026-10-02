import SwiftUI

/// Nuova Automazione: Progetto, name, request, model and Modalità autonoma (spec 19).
///
/// Outside git the Modalità autonoma is off, since the Esecuzioni have no copy of their own; in a Progetto not trusted
/// its rules do not apply. Both are said before Crea.
struct AutomationSheet: View {
    /// The Progetti of the Sessioni, most recent first, to pick from.
    let projects: [URL]
    /// Saves the new Automazione.
    let create: (Automation) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var project: URL?
    @State private var name = ""
    @State private var request = ""
    @State private var model = Automation.ModelChoice.router
    @State private var isAutonomous = true
    @State private var isChoosingFolder = false
    /// Whether the chosen Progetto is in a git repo; read again when it changes.
    @State private var isGit = true
    /// Whether `claude` trusts the chosen Progetto; read again when it changes.
    @State private var isTrusted = true

    /// The `claude` aliases offered besides the router.
    private static let aliases = ["opus", "sonnet", "haiku"]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            Text("Nuova Automazione")
                .font(Typography.body(size: 15, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Form {
                LabeledContent("Progetto") {
                    HStack {
                        Text(verbatim: project?.lastPathComponent ?? "")
                            .help(project?.path ?? "")
                        Button(project == nil ? "Scegli cartella…" : "Cambia…") { isChoosingFolder = true }
                    }
                }
                TextField("Nome", text: $name)
                LabeledContent("Richiesta") {
                    TextEditor(text: $request)
                        .font(Typography.body(size: 13))
                        .frame(minHeight: 80)
                        .scrollContentBackground(.hidden)
                        .background(Palette.surface)
                        .accessibilityLabel(Text("Richiesta"))
                }
                Picker("Modello", selection: $model) {
                    Text("Router").tag(Automation.ModelChoice.router)
                    ForEach(Self.aliases, id: \.self) { alias in
                        Text(verbatim: alias).tag(Automation.ModelChoice.fixed(alias: alias))
                    }
                }
                Toggle("Modalità autonoma", isOn: isGit ? $isAutonomous : .constant(false))
                    .disabled(!isGit)
            }
            if !isGit {
                Label("Il Progetto non è un repo git: niente copia isolata, quindi niente Modalità autonoma. Decidono solo le Regole.",
                      systemImage: "info.circle")
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !isTrusted {
                Label("Il Progetto non è fidato: le sue Regole non valgono nelle Esecuzioni.", systemImage: "lock")
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Annulla", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Crea", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCreate)
            }
        }
        .padding(Spacing.medium)
        .frame(width: 520)
        .onAppear { project = project ?? projects.first }
        .task(id: project) {
            isGit = project.map(AutomationStore.isGitRepository) ?? true
            isTrusted = project.map { TrustGate().isTrusted($0) } ?? true
        }
        .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
            if case let .success(folder) = result { project = folder }
        }
    }

    private var canCreate: Bool {
        project != nil && !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        guard let project else { return }
        create(Automation(id: UUID(), name: name.trimmingCharacters(in: .whitespaces), project: project,
                          request: request.trimmingCharacters(in: .whitespacesAndNewlines), model: model,
                          isAutonomous: isAutonomous && AutomationStore.isGitRepository(project)))
        dismiss()
    }
}

#Preview {
    AutomationSheet(projects: [URL(filePath: "/tmp")]) { _ in }
}
