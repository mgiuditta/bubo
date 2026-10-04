import SwiftUI

/// Nuova Automazione, or Modifica of one: Progetto, name, request, Ripetizione, model, agent and Modalità autonoma
/// (spec 19).
/// A Modifica counts from the next Esecuzione; the Regole and the history stay.
///
/// Outside git the Modalità autonoma is off, since the Esecuzioni have no copy of their own; in a Progetto not trusted
/// its rules do not apply. Both are said before Crea.
struct AutomationSheet: View {
    /// The Progetti of the Sessioni, most recent first, to pick from.
    let projects: [URL]
    /// The Automazione to change; `nil` for a new one.
    let editing: Automation?
    /// Saves the new or changed Automazione.
    let save: (Automation) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var project: URL?
    @State private var name: String
    @State private var request: String
    @State private var model: Automation.ModelChoice
    /// The agent the Esecuzioni run as; `nil` for the ordinary Sessione.
    @State private var agent: String?
    /// The agents of the chosen Progetto and of the user; read again when the Progetto changes.
    @State private var agents: [String] = []
    @State private var isAutonomous: Bool
    @State private var kind: RecurrenceKind
    /// The time of the Ripetizione; its day too for Una volta.
    @State private var time: Date
    /// The day of Un giorno della settimana, as `Calendar` counts them (1 is Sunday).
    @State private var weekday: Int
    @State private var isChoosingFolder = false
    /// Modello, Agente and Modalità autonoma: closed while they keep their defaults.
    @State private var isShowingAdvanced = false
    /// Whether the chosen Progetto is in a git repo; read again when it changes.
    @State private var isGit = true
    /// Whether `claude` trusts the chosen Progetto; read again when it changes.
    @State private var isTrusted = true

    /// The `claude` aliases offered besides the router.
    private static let aliases = ["opus", "sonnet", "haiku"]

    init(projects: [URL], editing: Automation? = nil, save: @escaping (Automation) -> Void) {
        self.projects = projects
        self.editing = editing
        self.save = save
        _project = State(initialValue: editing?.project)
        _name = State(initialValue: editing?.name ?? "")
        _request = State(initialValue: editing?.request ?? "")
        _model = State(initialValue: editing?.model ?? .router)
        _agent = State(initialValue: editing?.agent)
        _isAutonomous = State(initialValue: editing?.isAutonomous ?? true)
        let recurrence = editing?.recurrence ?? .daily(hour: 9, minute: 0)
        _kind = State(initialValue: RecurrenceKind(recurrence))
        _time = State(initialValue: RecurrenceKind.time(of: recurrence))
        let weekday = if case let .weekly(day, _, _) = recurrence { day } else { Calendar.autoupdatingCurrent.firstWeekday }
        _weekday = State(initialValue: weekday)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            Text(editing == nil ? "Nuova Automazione" : "Modifica Automazione")
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
                TextField("Nome", text: $name, prompt: Text("Facoltativo"))
                LabeledContent("Richiesta") {
                    TextEditor(text: $request)
                        .font(Typography.body(size: 13))
                        .frame(minHeight: 80)
                        .scrollContentBackground(.hidden)
                        .background(Palette.surface)
                        .accessibilityLabel(Text("Richiesta"))
                }
                Picker("Ripetizione", selection: $kind) {
                    ForEach(RecurrenceKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                if kind == .weekly {
                    Picker("Giorno", selection: $weekday) {
                        ForEach(Self.weekdays, id: \.self) { day in
                            Text(verbatim: Calendar.autoupdatingCurrent.weekdaySymbols[day - 1]).tag(day)
                        }
                    }
                }
                DatePicker(kind == .hourly ? "Minuto" : "Ora", selection: $time,
                           displayedComponents: kind == .once ? [.date, .hourAndMinute] : .hourAndMinute)
                // The defaults fit most Automazioni: the four questions above are what one needs.
                DisclosureGroup("Opzioni avanzate", isExpanded: $isShowingAdvanced) {
                    Picker("Modello", selection: $model) {
                        Text("Automatico").tag(Automation.ModelChoice.router)
                        ForEach(Self.aliases, id: \.self) { alias in
                            Text(verbatim: alias).tag(Automation.ModelChoice.fixed(alias: alias))
                        }
                    }
                    Picker("Agente", selection: $agent) {
                        Text("Nessuno").tag(String?.none)
                        ForEach(agentChoices, id: \.self) { name in
                            Text(verbatim: name).tag(Optional(name))
                        }
                    }
                    Toggle("Modalità autonoma", isOn: isGit ? $isAutonomous : .constant(false))
                        .disabled(!isGit)
                }
            }
            if kind == .once && time <= .now {
                Label("Scegli un'ora futura.", systemImage: "clock")
                    .foregroundStyle(Palette.textSecondary)
            }
            if !isGit {
                Label("Il Progetto non è un repo git: niente copia isolata, quindi niente Modalità autonoma. Decidono solo le Regole.",
                      systemImage: "info.circle")
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let agent, !agents.contains(agent) {
                Label("L'agente «\(agent)» non c'è più in questo Progetto: l'Automazione andrebbe in pausa. Scegline un altro.",
                      systemImage: "exclamationmark.triangle")
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
                Button(editing == nil ? "Crea" : "Salva", action: confirm)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCreate)
            }
        }
        .padding(Spacing.medium)
        .frame(width: 520)
        .onAppear {
            project = project ?? projects.first
            isShowingAdvanced = model != .router || agent != nil
        }
        .task(id: project) {
            isGit = project.map(AutomationStore.isGitRepository) ?? true
            isTrusted = project.map { TrustGate().isTrusted($0) } ?? true
            agents = project.map { AgentCatalog.runnableAgents(in: $0) } ?? []
        }
        .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
            if case let .success(folder) = result { project = folder }
        }
    }

    /// The days of the week, from the first one of the Mac's calendar.
    private static var weekdays: [Int] {
        let first = Calendar.autoupdatingCurrent.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }

    /// The agents to pick from, with the chosen one even when its file is gone, so that the choice shows.
    private var agentChoices: [String] {
        guard let agent, !agents.contains(agent) else { return agents }
        return agents + [agent]
    }

    private var canCreate: Bool {
        project != nil
            && !request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (kind != .once || time > .now) && agent.map(agents.contains) != false
    }

    private func confirm() {
        guard let project else { return }
        var automation = editing ?? Automation(id: UUID(), name: "", project: project, request: "")
        let text = request.trimmingCharacters(in: .whitespacesAndNewlines)
        let typed = name.trimmingCharacters(in: .whitespaces)
        // A name is one more thing to invent: without one, the start of the request.
        automation.name = typed.isEmpty ? String(text.prefix(40)) : typed
        automation.project = project
        automation.request = text
        automation.model = model
        automation.agent = agent
        automation.isAutonomous = isAutonomous && AutomationStore.isGitRepository(project)
        automation.recurrence = kind.recurrence(at: time, on: weekday)
        save(automation)
        dismiss()
    }
}

#Preview {
    AutomationSheet(projects: [URL(filePath: "/tmp")]) { _ in }
}
