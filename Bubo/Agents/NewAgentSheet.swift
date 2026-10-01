import os
import SwiftUI

/// Nuovo agente: Progetto or user, name and description; Crea writes the minimal file and opens it in the editor
/// (spec 19).
///
/// With a name already in that source, Crea is disabled and the sheet says why.
struct NewAgentSheet: View {
    /// Where the file goes.
    enum Destination: Hashable, CaseIterable, Identifiable {
        case project, user

        var id: Self { self }

        var title: LocalizedStringResource {
            switch self {
            case .project: "Progetto"
            case .user: "Utente"
            }
        }
    }

    /// The Progetto's folder.
    let project: URL
    /// The user's `~/.claude` folder.
    let user: URL
    /// The agents' files the window read, to refuse a name already there.
    let files: [AgentFile]
    /// Opens the file just written.
    let open: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var destination = Destination.project
    @State private var name = ""
    @State private var description = ""
    /// Why the file could not be written, as the disk says it.
    @State private var failure: String?

    private var writer: AgentFileWriter {
        switch destination {
        case .project:
            AgentFileWriter(folder: project.appending(path: ".claude/agents", directoryHint: .isDirectory),
                            existing: files.filter { $0.source == .project })
        case .user:
            AgentFileWriter(folder: user.appending(path: "agents", directoryHint: .isDirectory),
                            existing: files.filter { $0.source == .user })
        }
    }

    var body: some View {
        let refusal = writer.refusal(name: name, description: description)
        VStack(alignment: .leading, spacing: Spacing.medium) {
            Text("Nuovo agente")
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Form {
                Picker("Dove", selection: $destination) {
                    ForEach(Destination.allCases) { destination in
                        Text(destination.title).tag(destination)
                    }
                }
                .pickerStyle(.segmented)
                TextField("Nome", text: $name, prompt: Text(verbatim: "revisore"))
                TextField("Descrizione", text: $description, prompt: Text("Quando Claude deve usarlo"),
                          axis: .vertical)
                    .lineLimit(2...5)
                LabeledContent("File") {
                    Text(verbatim: writer.file(named: name.isEmpty ? "…" : name).path)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .textSelection(.enabled)
                }
            }
            Text("Bubo scrive solo nome e descrizione, poi apre il file nel tuo editor: il resto lo scrivi tu.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline) {
                if let failure {
                    Text(verbatim: failure)
                        .foregroundStyle(Palette.danger)
                        .textSelection(.enabled)
                } else if let refusal {
                    Text(refusal.message)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Annulla", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Crea e apri", action: create)
                    .keyboardShortcut(.defaultAction)
                    .disabled(refusal != nil)
                    .accessibilityHint(refusal.map { Text($0.message) } ?? Text(verbatim: ""))
            }
        }
        .padding(Spacing.medium)
        .frame(width: 520)
        .onChange(of: destination) { failure = nil }
        .onChange(of: name) { failure = nil }
    }

    /// Writes the file, after the click on Crea e apri, and opens it.
    private func create() {
        do {
            let file = try writer.write(name: name, description: description)
            Logger.agent.notice("New agent written in \(file.path, privacy: .private)")
            open(file)
            dismiss()
        } catch {
            failure = (error as? AgentFileWriter.Refusal).map { String(localized: $0.message) } ?? error.localizedDescription
        }
    }
}
