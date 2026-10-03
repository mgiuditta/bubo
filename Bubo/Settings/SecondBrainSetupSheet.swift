import SwiftUI
import UniformTypeIdentifiers

/// The guided setup of the Secondo cervello: one precise question per screen, each with a sensible default and
/// each skippable (#554). The answers become the folders the Indice reads and the ones `cerca` puts first.
struct SecondBrainSetupSheet: View {
    @Environment(SecondBrain.self) private var secondBrain
    @Environment(\.dismiss) private var dismiss
    @State private var step = SecondBrainSetupStep.folder
    /// The folders offered at the first question: the current one and the Obsidian vaults on this Mac.
    @State private var candidates: [URL] = []
    @State private var folder: URL?
    @State private var isChoosingFolder = false
    /// The folders at the top of the chosen Secondo cervello.
    @State private var topFolders: [String] = []
    @State private var includedFolders: Set<String> = []
    @State private var priorityFolders: Set<String> = []

    var body: some View {
        Form {
            Section {
                question
            } header: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Passo \(step.rawValue + 1) di \(SecondBrainSetupStep.allCases.count)")
                        .font(.callout)
                        .foregroundStyle(Palette.textSecondary)
                    Text(title)
                        .font(.title3.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                }
                .accessibilityElement(children: .combine)
            } footer: {
                Text(explanation)
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button("Salta tutto") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Salta") { advance() }
                Button(step.next == nil ? "Fine" : "Avanti") {
                    applyAnswer()
                    advance()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(step == .folder && folder == nil)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 460)
        .frame(minHeight: 340)
        .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
            guard case let .success(chosen) = result else { return }
            if !candidates.contains(chosen) { candidates.append(chosen) }
            folder = chosen
        }
        .task { loadCandidates() }
    }

    @ViewBuilder private var question: some View {
        switch step {
        case .folder:
            if candidates.isEmpty {
                Text("Non trovo vault di Obsidian su questo Mac. Va bene qualunque cartella di note Markdown.")
                    .foregroundStyle(Palette.textSecondary)
            } else {
                Picker("Cartella", selection: $folder) {
                    ForEach(candidates, id: \.self) { candidate in
                        Text(verbatim: candidate.lastPathComponent)
                            .help(candidate.path)
                            .tag(Optional(candidate))
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }
            Button("Scegli un'altra cartella…") { isChoosingFolder = true }
        case .includedFolders:
            if topFolders.isEmpty {
                Text("Nessuna sottocartella: leggo tutte le note.")
                    .foregroundStyle(Palette.textSecondary)
            }
            ForEach(topFolders, id: \.self) { name in
                Toggle(isOn: membership(of: name, in: $includedFolders)) {
                    Text(verbatim: name)
                }
            }
        case .priorityFolders:
            if includedFolders.isEmpty {
                Text("Nessuna sottocartella da mettere prima: cerco in tutte le note allo stesso modo.")
                    .foregroundStyle(Palette.textSecondary)
            }
            ForEach(topFolders.filter(includedFolders.contains), id: \.self) { name in
                Toggle(isOn: membership(of: name, in: $priorityFolders)) {
                    Text(verbatim: name)
                }
            }
        }
    }

    private var title: LocalizedStringKey {
        switch step {
        case .folder: "Dove sono le tue note?"
        case .includedFolders: "Quali cartelle leggo?"
        case .priorityFolders: "Quali cartelle contano di più?"
        }
    }

    private var explanation: LocalizedStringKey {
        switch step {
        case .folder: "Leggo le note solo quando le cerco e scrivo solo nella cartella Bubo. Obsidian può restare chiuso."
        case .includedFolders: "Le cartelle spente restano dove sono, ma non le leggo. Di solito si spengono archivi e allegati."
        case .priorityFolders: "Quando la ricerca trova note in cartelle diverse, quelle scelte qui vengono prima. Puoi cambiarle in Impostazioni."
        }
    }

    /// Whether `name` is in `folders`, as a switch.
    private func membership(of name: String, in folders: Binding<Set<String>>) -> Binding<Bool> {
        Binding {
            folders.wrappedValue.contains(name)
        } set: { isOn in
            if isOn { folders.wrappedValue.insert(name) } else { folders.wrappedValue.remove(name) }
        }
    }

    /// Offers the current folder and the vaults, the current folder or else the first vault chosen.
    private func loadCandidates() {
        let current = secondBrain.location?.url
        let vaults = SecondBrainLocation.suggestedVaults().filter { $0.standardizedFileURL != current?.standardizedFileURL }
        candidates = (current.map { [$0] } ?? []) + vaults
        folder = candidates.first
    }

    /// Reads the folders at the top of the Secondo cervello and the answers already given about them.
    private func loadFolders() {
        guard let location = secondBrain.location else { return }
        topFolders = location.topFolders()
        includedFolders = Set(topFolders).subtracting(location.excludedFolders)
        priorityFolders = Set(location.priorityFolders).intersection(topFolders)
    }

    /// Saves the answer to the current question. Folders deeper than the top, chosen in Impostazioni, stay as they are.
    private func applyAnswer() {
        switch step {
        case .folder:
            guard let folder, folder.standardizedFileURL != secondBrain.location?.url.standardizedFileURL else { return }
            secondBrain.choose(folder)
        case .includedFolders:
            guard let location = secondBrain.location else { return }
            let deeper = location.excludedFolders.filter { !topFolders.contains($0) }
            secondBrain.excludeOnly(Set(deeper).union(Set(topFolders).subtracting(includedFolders)))
        case .priorityFolders:
            guard let location = secondBrain.location else { return }
            let deeper = location.priorityFolders.filter { !topFolders.contains($0) }
            secondBrain.prioritizeOnly(Set(deeper).union(priorityFolders))
        }
    }

    /// Goes to the next question, or closes after the last one or when no folder was chosen.
    private func advance() {
        guard let next = step.next, secondBrain.location != nil else {
            dismiss()
            return
        }
        if step == .folder { loadFolders() }
        step = next
    }
}
