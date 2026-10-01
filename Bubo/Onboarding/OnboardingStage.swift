import SwiftUI

/// The first launch under the Orb (spec 26): what the Orb says, the recent Progetti, and the input bar with three
/// suggested questions. No window and no sheet: the Open panel appears only when the user asks for it.
///
/// From the keyboard: ↑↓ choose among the recent Progetti, ↩ sends, ⌘O opens another folder.
struct OnboardingStage: View {
    @Bindable var flow: OnboardingFlow
    /// The recent Progetto under the arrow keys.
    @State private var highlighted: RecentProject?
    @State private var isChoosingFolder = false
    /// Where the Open panel starts: the protected recent Progetto the user picked, or the panel's own default.
    @State private var folderToOpen: URL?
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: Spacing.medium) {
            Text(flow.orbLine)
                .font(Typography.body(size: 20))
                .foregroundStyle(Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("onboarding.orbLine")
            if flow.readiness != nil { projects }
            input
            suggestions
        }
        .onAppear { isInputFocused = true }
        // The focus stays in the input bar: VoiceOver hears what the Orb asks next without moving there.
        .onChange(of: String(localized: flow.orbLine)) { _, line in
            AccessibilityNotification.Announcement(line).post()
        }
        .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
            if case let .success(folder) = result { flow.choose(folder) }
        }
        .fileDialogDefaultDirectory(folderToOpen)
    }

    private var projects: some View {
        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
            ForEach(flow.recents) { recent in
                Button { pick(recent) } label: {
                    row(name: recent.folder.lastPathComponent, path: recent.folder.path,
                        isSelected: isChosen(recent.folder) || highlighted == recent)
                }
                .buttonStyle(.plain)
                .help(recent.folder.path)
                .accessibilityAddTraits(isChosen(recent.folder) ? .isSelected : [])
            }
            if let project = flow.project, !flow.recents.contains(where: { $0.folder == project }) {
                row(name: project.lastPathComponent, path: project.path, isSelected: true)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isSelected)
            }
            Button {
                folderToOpen = nil
                isChoosingFolder = true
            } label: {
                Text("Scegli un'altra cartella…")
                    .font(Typography.body(size: 14))
                    .padding(.horizontal, Spacing.small)
                    .padding(.vertical, Spacing.xSmall)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.textSecondary)
            .keyboardShortcut("o")
            .accessibilityIdentifier("onboarding.openFolder")
        }
        .frame(maxWidth: 560, alignment: .leading)
    }

    private func row(name: String, path: String, isSelected: Bool) -> some View {
        HStack(spacing: Spacing.small) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "folder")
                .foregroundStyle(isSelected ? Palette.accent : Palette.textSecondary)
                .accessibilityHidden(true)
            Text(verbatim: name)
                .font(Typography.body(size: 14))
                .foregroundStyle(Palette.textPrimary)
            Text(verbatim: path)
                .font(Typography.mono(size: 11))
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.small)
        .padding(.vertical, Spacing.xSmall)
        .background(isSelected ? Palette.surface : .clear, in: .rect(cornerRadius: CornerRadius.medium))
        .contentShape(.rect)
    }

    private var input: some View {
        TextField("Chiedi qualcosa a Claude", text: $flow.draft)
            .textFieldStyle(.plain)
            .font(Typography.body(size: 15))
            .focused($isInputFocused)
            .onSubmit(send)
            .onKeyPress(.downArrow) { move(by: 1) }
            .onKeyPress(.upArrow) { move(by: -1) }
            // On macOS the title is only a placeholder, so VoiceOver would find a nameless field.
            .accessibilityLabel("Chiedi qualcosa a Claude")
            .accessibilityIdentifier("onboarding.prompt")
            .padding(Spacing.small)
            .background(Palette.surface, in: .rect(cornerRadius: CornerRadius.large))
            .overlay {
                RoundedRectangle(cornerRadius: CornerRadius.large).strokeBorder(Palette.line)
            }
            .frame(maxWidth: 560)
    }

    private var suggestions: some View {
        HStack(spacing: Spacing.xSmall) {
            ForEach(OnboardingFlow.suggestions.indices, id: \.self) { index in
                Button {
                    flow.draft = String(localized: OnboardingFlow.suggestions[index])
                    isInputFocused = true
                } label: {
                    Text(OnboardingFlow.suggestions[index])
                        .font(Typography.body(size: 12))
                        .padding(.horizontal, Spacing.small)
                        .padding(.vertical, Spacing.xxSmall)
                        .overlay(Capsule().strokeBorder(Palette.line))
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.textSecondary)
            }
        }
    }

    private func isChosen(_ folder: URL) -> Bool {
        flow.project == folder
    }

    /// Chooses `recent`; a protected one through the Open panel, already on its folder.
    private func pick(_ recent: RecentProject) {
        highlighted = recent
        if recent.isProtected {
            folderToOpen = recent.folder
            isChoosingFolder = true
        } else {
            flow.choose(recent.folder)
        }
    }

    /// Moves the highlight among the recent Progetti, choosing the ones Bubo may open on its own.
    private func move(by offset: Int) -> KeyPress.Result {
        guard !flow.recents.isEmpty else { return .ignored }
        let current = highlighted.flatMap(flow.recents.firstIndex(of:)) ?? (offset > 0 ? -1 : flow.recents.count)
        let recent = flow.recents[min(max(current + offset, 0), flow.recents.count - 1)]
        highlighted = recent
        if !recent.isProtected { flow.choose(recent.folder) }
        return .handled
    }

    /// Sends the question; with a protected Progetto under the highlight, opens the panel on it so the question can
    /// start there.
    private func send() {
        flow.send()
        if flow.project == nil, let highlighted, highlighted.isProtected { pick(highlighted) }
    }
}

#Preview {
    let flow = OnboardingFlow(hasSessions: false, defaults: UserDefaults(suiteName: "preview") ?? .standard) { _, _ in }
    flow.readiness = .ready(version: "2.1.286", method: "Max")
    flow.show([RecentProject(folder: URL(filePath: "/Users/ada/Sviluppo/bubo"), isProtected: false),
               RecentProject(folder: URL(filePath: "/Users/ada/Documents/tesi"), isProtected: true)])
    return OnboardingStage(flow: flow)
        .padding()
        .background(Palette.ink)
}
