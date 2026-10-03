import SwiftUI
import UniformTypeIdentifiers

/// The setup of the Secondo cervello, «Personalizza a fondo»: the user chooses the folder (the current one, a vault,
/// any folder or a new one), then the model they pick interviews them in the Bolla of the Orb (``SecondBrainConversation``).
struct SecondBrainConversationSheet: View {
    @Environment(SecondBrain.self) private var secondBrain
    @Environment(QuestionModel.self) private var questions
    @Environment(SecondBrainConversation.self) private var conversation
    @Environment(\.dismiss) private var dismiss
    @State private var isChoosingFolder = false
    /// The folders offered before the conversation: the current one first, then the Obsidian vaults on this Mac.
    @State private var candidates: [URL] = []
    @State private var chosen: URL?

    /// Where a new Secondo cervello is created.
    private static let newFolder = URL.documentsDirectory.appending(path: "Secondo cervello", directoryHint: .isDirectory)

    var body: some View {
        chooser
            .frame(width: 520, height: 520)
            .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
                guard case let .success(folder) = result else { return }
                if !candidates.contains(folder) { candidates.append(folder) }
                chosen = folder
            }
            .task {
                let current = secondBrain.location?.url
                candidates = (current.map { [$0] } ?? [])
                    + SecondBrainLocation.suggestedVaults().filter { $0.standardizedFileURL != current?.standardizedFileURL }
                chosen = current ?? candidates.first
            }
    }

    /// The choice of the folder, which is the user's alone.
    private var chooser: some View {
        Form {
            Section {
                Picker("Cartella", selection: $chosen) {
                    ForEach(candidates, id: \.self) { candidate in
                        Group {
                            if candidate.standardizedFileURL == secondBrain.location?.url.standardizedFileURL {
                                Text("\(candidate.lastPathComponent) (configurata)")
                            } else {
                                Text(verbatim: candidate.lastPathComponent)
                            }
                        }
                        .help(candidate.path)
                        .tag(Optional(candidate))
                    }
                    Text("Nuovo Secondo cervello").tag(Optional(Self.newFolder))
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                Button("Scegli un'altra cartella…") { isChoosingFolder = true }
            } header: {
                Text("Quale cartella?")
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
            } footer: {
                Text("Il modello che scegli ti fa qualche giro di domande accanto all'Orb, poi ti mostra la mappa. Non scrivo nulla finché non dici sì.")
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom) {
            HStack {
                ModelPicker(model: questions)
                Spacer()
                Button("Annulla") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Avanti") {
                    guard let chosen else { return }
                    let isNew = chosen == Self.newFolder && !FileManager.default.fileExists(atPath: chosen.path)
                    dismiss()
                    conversation.start(with: chosen, isNew: isNew)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(chosen == nil)
            }
            .padding([.horizontal, .bottom], 20)
        }
    }
}
