import SwiftUI
import UniformTypeIdentifiers

/// The guided setup of the Riunioni: one precise question per screen, each with a sensible default and each skippable
/// (#554, #563), after the folder of the Secondo cervello when there is none. The rest of the Secondo cervello is set
/// up in a conversation (``SecondBrainConversationSheet``).
struct SecondBrainSetupSheet: View {
    /// The questions asked, in order.
    var steps = SecondBrainSetupStep.allCases
    @Environment(SecondBrain.self) private var secondBrain
    @Environment(\.dismiss) private var dismiss
    @State private var position = 0
    /// The folders offered at the first question: the current one and the Obsidian vaults on this Mac.
    @State private var candidates: [URL] = []
    @State private var folder: URL?
    @State private var isChoosingFolder = false
    @State private var callServices: Set<CallService> = []
    @State private var meetingAudio = MeetingAudioRetention.thirtyDays
    /// A code of ``MeetingLanguage/offered``, or empty for the Mac's language.
    @State private var meetingLanguage = ""

    private var step: SecondBrainSetupStep { steps[position] }
    private var isLast: Bool { position == steps.count - 1 }

    var body: some View {
        Form {
            Section {
                question
            } header: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Passo \(position + 1) di \(steps.count)")
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
                // On the folder «Salta» would do what «Salta tutto» does: one way out is enough.
                if step != .folder {
                    Button("Salta") { advance() }
                }
                Button(isLast ? "Fine" : "Avanti") {
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
        .task {
            loadCandidates()
            loadMeetingAnswers()
        }
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
        case .callServices:
            ForEach(CallService.allCases) { service in
                Toggle(isOn: membership(of: service, in: $callServices)) {
                    Text(verbatim: service.name)
                }
            }
        case .meetingAudio:
            Picker("Audio delle Riunioni", selection: $meetingAudio) {
                Text("Conserva per 30 giorni").tag(MeetingAudioRetention.thirtyDays)
                Text("Elimina dopo la trascrizione").tag(MeetingAudioRetention.afterTranscription)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
        case .meetingLanguage:
            Picker("Lingua delle Riunioni", selection: $meetingLanguage) {
                Text("La lingua del Mac").tag("")
                ForEach(MeetingLanguage.offered, id: \.self) { code in
                    Text(verbatim: Locale.current.localizedString(forLanguageCode: code)?.localizedCapitalized ?? code)
                        .tag(code)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
        }
    }

    private var title: LocalizedStringKey {
        switch step {
        case .folder: "Dove sono le tue note?"
        case .callServices: "Che app usi per le Riunioni?"
        case .meetingAudio: "Per quanto tengo l'audio delle Riunioni?"
        case .meetingLanguage: "In che lingua sono le Riunioni?"
        }
    }

    private var explanation: LocalizedStringKey {
        switch step {
        case .folder: "Leggo le note solo quando le cerco e scrivo solo nella cartella Bubo. Obsidian può restare chiuso."
        case .callServices: "Quando registri una Riunione, propongo prima queste app. Ho già attivato quelle installate."
        case .meetingAudio: "L'audio resta sul Mac, mai nel Secondo cervello. Nella nota c'è sempre la trascrizione."
        case .meetingLanguage: "Trascrivo le Riunioni sul Mac, in questa lingua. La prima volta scarico il modello."
        }
    }

    /// Whether `member` is in `members`, as a switch.
    private func membership<Member: Hashable>(of member: Member, in members: Binding<Set<Member>>) -> Binding<Bool> {
        Binding {
            members.wrappedValue.contains(member)
        } set: { isOn in
            if isOn { members.wrappedValue.insert(member) } else { members.wrappedValue.remove(member) }
        }
    }

    /// Offers the current folder and the vaults, the current folder or else the first vault chosen.
    private func loadCandidates() {
        let current = secondBrain.location?.url
        let vaults = SecondBrainLocation.suggestedVaults().filter { $0.standardizedFileURL != current?.standardizedFileURL }
        candidates = (current.map { [$0] } ?? []) + vaults
        folder = candidates.first
    }

    /// Reads the answers about the Riunioni already given: the call services installed when none was chosen.
    private func loadMeetingAnswers() {
        let saved = CallService.saved()
        callServices = saved.isEmpty ? CallService.installed() : Set(saved)
        meetingAudio = MeetingAudioRetention.saved(in: .standard)
        meetingLanguage = UserDefaults.standard.string(forKey: MeetingLanguage.defaultsKey) ?? ""
    }

    /// Saves the answer to the current question.
    private func applyAnswer() {
        switch step {
        case .folder:
            guard let folder, folder.standardizedFileURL != secondBrain.location?.url.standardizedFileURL else { return }
            secondBrain.choose(folder)
        case .callServices:
            CallService.save(callServices)
        case .meetingAudio:
            UserDefaults.standard.set(meetingAudio.rawValue, forKey: MeetingAudioRetention.defaultsKey)
        case .meetingLanguage:
            if meetingLanguage.isEmpty {
                UserDefaults.standard.removeObject(forKey: MeetingLanguage.defaultsKey)
            } else {
                UserDefaults.standard.set(meetingLanguage, forKey: MeetingLanguage.defaultsKey)
            }
        }
    }

    /// Goes to the next question, or closes after the last one or when no folder was chosen.
    private func advance() {
        guard !isLast, secondBrain.location != nil else {
            dismiss()
            return
        }
        position += 1
    }
}
