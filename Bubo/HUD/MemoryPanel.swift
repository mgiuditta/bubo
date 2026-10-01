import CoreServices
import os
import SwiftUI

/// The Memoria di Progetto: the CLAUDE.md that `claude` loads, the `MEMORY.md` index with how full it is, and the
/// memories Claude saved, with their kind and date (spec 13).
///
/// Everything is read again from the disk when the panel opens and on each file event: auto-dream, the CLI or a
/// Sessione may change the memory at any time. Bubo writes only when the user saves or deletes, and never while a
/// Sessione of the Progetto is in a turn, so that `MEMORY.md` never has two writers.
struct MemoryPanel: View {
    /// The Progetto's folder.
    let project: URL
    /// Whether a Sessione of the Progetto is in a turn: its agent may be writing the memory.
    let isInTurn: Bool
    /// Reads the configuration `claude` loads in a folder, for its CLAUDE.md.
    let read: (URL) async throws -> ClaudeConfiguration
    @Environment(\.dismiss) private var dismiss
    @State private var memory: ProjectMemory?
    @State private var instructions: [ClaudeConfiguration.Instructions]?
    @State private var instructionsFailed = false
    /// When each file changed on disk while the panel was open and no Sessione of the Progetto was in a turn.
    @State private var changedOutside: [String: Date] = [:]
    @State private var editing: MemoryFile?
    @State private var deleting: MemoryDeletion.Request?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            if let memory {
                form(memory)
            } else {
                LoadingLabel("Leggo la memoria del Progetto…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack {
                Spacer()
                Button("Chiudi") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(Spacing.medium)
        .frame(width: 560, height: 640)
        .task { await watch() }
        .task { await readInstructions() }
        .sheet(item: $editing) { file in
            MemoryEditor(file: file, isInTurn: isInTurn) { await reload() }
        }
        .sheet(item: $deleting) { request in
            MemoryDeletion(request: request, isInTurn: isInTurn) { await reload() }
        }
    }

    private func form(_ memory: ProjectMemory) -> some View {
        Form {
            Section {
                Text(verbatim: memory.directory.path)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                if isInTurn {
                    Label("Una Sessione del Progetto sta lavorando: potrai modificare i ricordi quando si ferma.",
                          systemImage: "lock")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Memoria del Progetto")
            }

            instructionsSection

            indexSection(memory)

            Section("Ricordi · \(memory.topics.count)") {
                if memory.topics.isEmpty {
                    Text("Claude non ha ancora salvato ricordi in questo Progetto.")
                        .foregroundStyle(.secondary)
                }
                ForEach(memory.topics) { topic in
                    MemoryTopicRow(topic: topic, changedOutside: changedOutside[topic.name], isInTurn: isInTurn) {
                        editing = MemoryFile(directory: memory.directory, name: topic.name, text: topic.text)
                    } delete: {
                        deleting = MemoryDeletion.Request(memory: memory, topic: topic)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private var instructionsSection: some View {
        Section("CLAUDE.md caricati") {
            if let instructions {
                if instructions.isEmpty {
                    Text("Nessun CLAUDE.md caricato.")
                        .foregroundStyle(.secondary)
                }
                ForEach(instructions, id: \.path) { file in
                    LabeledContent {
                        Text(file.level)
                    } label: {
                        Text(verbatim: file.path)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                    }
                }
            } else if instructionsFailed {
                Text("Non riesco a sapere quali CLAUDE.md carica Claude. Controlla che la CLI claude funzioni nel Terminale, poi riapri il pannello.")
                    .foregroundStyle(.secondary)
            } else {
                LoadingLabel("Chiedo a Claude quali CLAUDE.md carica…")
            }
        }
    }

    private func indexSection(_ memory: ProjectMemory) -> some View {
        Section {
            if let index = memory.index {
                MemoryIndexGauge(index: index)
                if let date = changedOutside[ProjectMemory.indexName] {
                    ChangedOutsideLabel(date: date)
                }
                Button("Modifica l'indice…") {
                    editing = MemoryFile(directory: memory.directory, name: ProjectMemory.indexName, text: index.text)
                }
                .disabled(isInTurn)
            } else {
                Text("Nessun indice: Claude lo crea quando salva il primo ricordo.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(verbatim: ProjectMemory.indexName)
        }
    }

    // MARK: Reading

    /// Reads the memory now, then again on every file event under it, until the panel closes.
    private func watch() async {
        await reload()
        guard let directory = memory?.directory else { return }
        // FSEvents reports real paths, and watches only folders that exist: `projects` does once `claude` ever ran.
        let projects = directory.deletingLastPathComponent().deletingLastPathComponent()
        let watched = TrustGate.realPath(projects.path)
        let prefix = watched + "/" + directory.deletingLastPathComponent().lastPathComponent + "/memory"
        for await batch in FileEvents.batches(under: watched, since: FSEventStreamEventId(kFSEventStreamEventIdSinceNow)) {
            guard batch.needsRescan || batch.paths.contains(where: { $0.hasPrefix(prefix) }) else { continue }
            await reload()
        }
    }

    /// Reads the memory from the disk; a file that changed outside a turn of the Progetto's Sessioni, and not through
    /// this panel, is marked as changed outside Bubo.
    private func reload() async {
        let directory = memory?.directory ?? ProjectMemory.directory(ofProject: project)
        let fresh = await ProjectMemory.reading(in: directory)
        if let memory, !isInTurn {
            for name in Self.changedFiles(from: memory, to: fresh) {
                let file = directory.appending(path: name)
                changedOutside[name] = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .now
            }
        }
        memory = fresh
    }

    /// The files whose text differs between two reads, or that appeared.
    private static func changedFiles(from old: ProjectMemory, to new: ProjectMemory) -> [String] {
        var texts = Dictionary(uniqueKeysWithValues: old.topics.map { ($0.name, $0.text) })
        texts[ProjectMemory.indexName] = old.index?.text
        var changed = new.topics.filter { texts[$0.name] != $0.text }.map(\.name)
        if let index = new.index, index.text != texts[ProjectMemory.indexName] { changed.append(ProjectMemory.indexName) }
        return changed
    }

    private func readInstructions() async {
        do {
            instructions = try await read(project).instructions.filter { !$0.isAutoMemory }
        } catch is CancellationError {
        } catch {
            Logger.memory.error("CLAUDE.md not read: \(String(describing: error), privacy: .private)")
            instructionsFailed = true
        }
    }
}

/// A memory file open for editing: where it is and the text read from the disk.
struct MemoryFile: Identifiable {
    let directory: URL
    let name: String
    let text: String

    var id: String { name }
}

/// How full `MEMORY.md` is against the limits that Claude Code loads, with a warning past 80%.
private struct MemoryIndexGauge: View {
    let index: ProjectMemory.Index

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Gauge(value: min(index.fill, 1)) {
                Text("Occupazione")
            } currentValueLabel: {
                Text(index.fill, format: .percent.precision(.fractionLength(0)))
            }
            .gaugeStyle(.linearCapacity)
            .tint(index.isNearLimit ? Palette.danger : Palette.accent)
            Text("\(index.lineCount) righe su \(ProjectMemory.lineLimit) · \(Int64(index.byteCount).formatted(.byteCount(style: .file))) su \(Int64(ProjectMemory.byteLimit).formatted(.byteCount(style: .file)))")
                .font(.callout)
                .foregroundStyle(.secondary)
            if index.isNearLimit {
                Label {
                    Text("L'indice è quasi pieno. Oltre \(ProjectMemory.lineLimit) righe o \(Int64(ProjectMemory.byteLimit).formatted(.byteCount(style: .file))) Claude non carica il resto: accorcialo o chiedi a Claude di riordinarlo.")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Palette.danger)
                        .accessibilityHidden(true)
                }
            }
        }
    }
}

/// A memory: its title, kind and date, what it is about, and Modifica and Cancella.
private struct MemoryTopicRow: View {
    let topic: ProjectMemory.Topic
    let changedOutside: Date?
    let isInTurn: Bool
    let edit: () -> Void
    let delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
            LabeledContent {
                HStack(spacing: Spacing.xSmall) {
                    Button("Modifica…", action: edit)
                    Button("Cancella…", role: .destructive, action: delete)
                }
                .disabled(isInTurn)
            } label: {
                Text(verbatim: topic.title ?? topic.name)
                Text(details)
            }
            if let summary = topic.summary {
                Text(verbatim: summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let changedOutside {
                ChangedOutsideLabel(date: changedOutside)
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// The kind, the file and the date of the last write.
    private var details: String {
        var parts = [topic.kind.map { String(localized: Self.title(ofKind: $0)) }, topic.name]
        parts.append(topic.modified?.formatted(date: .abbreviated, time: .shortened))
        return parts.compactMap(\.self).joined(separator: " · ")
    }

    private static func title(ofKind kind: String) -> LocalizedStringResource {
        switch kind {
        case "user": "Utente"
        case "feedback": "Feedback"
        case "project": "Progetto"
        case "reference": "Riferimento"
        default: LocalizedStringResource(stringLiteral: kind)
        }
    }
}

/// "Cambiato fuori da Bubo", with when.
private struct ChangedOutsideLabel: View {
    let date: Date

    var body: some View {
        Label("Cambiato fuori da Bubo · \(date.formatted(date: .omitted, time: .shortened))",
              systemImage: "arrow.triangle.2.circlepath")
            .font(.callout)
            .foregroundStyle(Palette.textSecondary)
    }
}

#Preview {
    MemoryPanel(project: URL(filePath: "/Users/u/Sviluppo/bubo"), isInTurn: false) { _ in
        ClaudeConfiguration(skills: [], plugins: [], pluginErrors: [], mcpServers: [],
                            instructions: [.init(path: "/Users/u/Sviluppo/bubo/CLAUDE.md", type: "Project")])
    }
}
