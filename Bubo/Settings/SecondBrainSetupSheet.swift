import SwiftUI
import UniformTypeIdentifiers

/// The guided setup of the Secondo cervello: one precise question per screen, each with a sensible default and
/// each skippable (#554, #563). The answers become the folders the Indice reads, the folders, people and projects
/// `cerca` puts first, and how the Riunioni are recorded.
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
    /// The folders at the top of the chosen Secondo cervello.
    @State private var topFolders: [String] = []
    @State private var includedFolders: Set<String> = []
    @State private var priorityFolders: Set<String> = []
    /// The people and projects, as typed: names separated by commas.
    @State private var people = ""
    @State private var projects = ""
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
                Button("Salta") { advance() }
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
            loadProfile()
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
        case .people:
            TextField("Persone", text: $people, prompt: Text("Giulia Rossi, Marco"))
        case .projects:
            TextField("Progetti", text: $projects, prompt: Text("Bubo, Sito nuovo"))
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
        case .includedFolders: "Quali cartelle leggo?"
        case .priorityFolders: "Quali cartelle contano di più?"
        case .people: "Con chi lavori più spesso?"
        case .projects: "Quali progetti segui?"
        case .callServices: "Che app usi per le Riunioni?"
        case .meetingAudio: "Per quanto tengo l'audio delle Riunioni?"
        case .meetingLanguage: "In che lingua sono le Riunioni?"
        }
    }

    private var explanation: LocalizedStringKey {
        switch step {
        case .folder: "Leggo le note solo quando le cerco e scrivo solo nella cartella Bubo. Obsidian può restare chiuso."
        case .includedFolders: "Le cartelle spente restano dove sono, ma non le leggo. Di solito si spengono archivi e allegati."
        case .priorityFolders: "Quando la ricerca trova note in cartelle diverse, quelle scelte qui vengono prima. Puoi cambiarle in Impostazioni."
        case .people: "Nomi separati da virgole. Le note che li nominano vengono prima nella ricerca."
        case .projects: "Nomi separati da virgole. Le note che li nominano vengono prima nella ricerca."
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

    /// Reads the folders at the top of the Secondo cervello and the answers already given about them.
    private func loadFolders() {
        guard let location = secondBrain.location else { return }
        topFolders = location.topFolders()
        includedFolders = Set(topFolders).subtracting(location.excludedFolders)
        priorityFolders = Set(location.priorityFolders).intersection(topFolders)
    }

    /// Reads the people and projects already named.
    private func loadProfile() {
        people = (secondBrain.location?.people ?? []).joined(separator: ", ")
        projects = (secondBrain.location?.projects ?? []).joined(separator: ", ")
    }

    /// Reads the answers about the Riunioni already given: the call services installed when none was chosen.
    private func loadMeetingAnswers() {
        let saved = CallService.saved()
        callServices = saved.isEmpty ? CallService.installed() : Set(saved)
        meetingAudio = MeetingAudioRetention.saved(in: .standard)
        meetingLanguage = UserDefaults.standard.string(forKey: MeetingLanguage.defaultsKey) ?? ""
        if steps.contains(.callServices) {
            UserDefaults.standard.set(true, forKey: SecondBrainSetupStep.meetingsShownKey)
        }
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
        case .people:
            secondBrain.prioritize(people: SecondBrainLocation.names(in: people), projects: secondBrain.location?.projects ?? [])
        case .projects:
            secondBrain.prioritize(people: secondBrain.location?.people ?? [], projects: SecondBrainLocation.names(in: projects))
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
        if step == .folder {
            loadFolders()
            loadProfile()
        }
        position += 1
    }
}
