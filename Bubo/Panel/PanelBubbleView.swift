import SwiftUI

/// The bubble beside the Orb: the subtitles of the Sintesi parlata, the prompt, and the answer as it streams.
///
/// It shows the Domanda of the HUD, so there is one Domanda only; "Rifai con…" and the Sessione open in the HUD.
struct PanelBubbleView: View {
    let bubble: PanelBubble
    @Bindable var model: QuestionModel
    let hud: HUDPresenter
    /// The interview that sets up the Secondo cervello, when the Domanda is it.
    let brainSetup: SecondBrainConversation
    /// Called with the content's size whenever it changes, to fit the window around it.
    var onResize: (CGSize) -> Void = { _ in }
    @FocusState private var promptHasFocus: Bool
    @Environment(\.accessibilityReduceTransparency) private var reducesTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    /// The bubble's width, in points; the height follows the content.
    static let width: CGFloat = 460

    var body: some View {
        ZStack {
            if bubble.isOpen {
                content
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGSize.self, of: \.size, action: onResize)
                    .transition(transition)
                    // From the opening too: the field is new each time the bubble opens.
                    .onChange(of: bubble.takesKeyboard, initial: true) { _, takesKeyboard in
                        if takesKeyboard { promptHasFocus = true }
                    }
            }
        }
        .animation(bubble.appearance == .grow ? Motion.emphasized : Motion.quick, value: bubble.isOpen)
        // Once, at the end: VoiceOver would read every chunk of the stream otherwise.
        .onChange(of: model.isAnswering) { wasAnswering, isAnswering in
            guard bubble.isOpen,
                  let announcement = PanelBubble.announcement(wasAnswering: wasAnswering, isAnswering: isAnswering,
                                                              answer: model.answer)
            else { return }
            AccessibilityNotification.Announcement(announcement).post()
        }
    }

    /// Grows from the Orb and shrinks back into it, or grows on into the HUD; only fades with Riduci movimento.
    private var transition: AnyTransition {
        .modifier(active: BubbleMotion(bubble: bubble, isPresented: false),
                  identity: BubbleMotion(bubble: bubble, isPresented: true))
    }

    private var content: some View {
        GlassEffectContainer {
            // The bubble stops at half the screen and scrolls; the scroll view hugs its content below that.
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.medium) {
                    // The Sintesi parlata as subtitles, while Bubo says it; VoiceOver users hear the voice already.
                    if let subtitle = model.subtitle {
                        Text(verbatim: subtitle)
                            .font(Typography.body(size: 15))
                            .foregroundStyle(Palette.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityHidden(true)
                    }
                    // The Domanda's turns in a column: each prompt as a small line, its whole answer under it.
                    ForEach(Array(model.turns.enumerated()), id: \.offset) { _, turn in
                        turnPrompt(turn.prompt)
                        AnswerProse(prose: SecondBrainProposal.prose(of: turn.answer))
                    }
                    if !model.lastPrompt.isEmpty {
                        turnPrompt(model.lastPrompt)
                    }
                    if model.copilotNotesQuestion != nil {
                        CopilotNotesQuestion(allow: { model.answerCopilotNotesQuestion(allowing: true) },
                                             decline: { model.answerCopilotNotesQuestion(allowing: false) })
                    }
                    if let notice = bubble.notice {
                        ErrorNotice("Sessione non creata", remedy: "\(notice)", actionTitle: "Chiudi", action: bubble.close)
                            .transition(.opacity)
                    } else if let failure = model.failure {
                        QuestionNotice(failure: failure, model: model, pickRetry: hud.show)
                            .transition(.opacity)
                    } else if model.isAnswering && model.answer.isEmpty {
                        LoadingLabel("Sto pensando…")
                            .transition(.opacity)
                    } else if !model.answer.isEmpty {
                        // As tall as the bubble lets it: the bubble scrolls past half the screen.
                        QuestionAnswer(model: model, pickRetry: hud.show, maxAnswerHeight: nil)
                            .transition(.opacity)
                    }
                    SecondBrainProposalCard(conversation: brainSetup)
                    if let savedChange = model.savedChange {
                        SavedNoteLine(change: savedChange, undo: model.undoSavedChange)
                    }
                    // What was dropped on the Orb, waiting for the Domanda about it.
                    if !model.attachments.isEmpty {
                        AttachmentChips(attachments: model.attachments, remove: model.detach)
                    }
                    SessionProposalButton(model: model, hud: hud)
                    // Under the turns, as the next one follows them.
                    prompt
                    // On its own line, so a long reason truncates instead of pushing the bubble past its width.
                    ModelPicker(model: model)
                }
                .padding(Spacing.large)
                .animation(Motion.isReduced ? nil : Motion.standard, value: contentPhase)
            }
            .scrollBounceBehavior(.basedOnSize)
            // Follows the answer as it streams once the bubble scrolls.
            .defaultScrollAnchor(.bottom, for: .sizeChanges)
            .frame(maxHeight: bubble.maxHeight)
            .frame(width: Self.width, alignment: .leading)
            .background {
                // Opaque graphite with Riduci trasparenza or Aumenta contrasto, as the status pill: a bright desktop
                // could show through the glass behind the answer.
                if isOpaque {
                    RoundedRectangle(cornerRadius: CornerRadius.panel).fill(Palette.ink)
                    RoundedRectangle(cornerRadius: CornerRadius.panel).fill(Palette.surface)
                }
            }
            .glassEffect(isOpaque ? .identity : .regular, in: .rect(cornerRadius: CornerRadius.panel))
            .overlay {
                if isOpaque {
                    RoundedRectangle(cornerRadius: CornerRadius.panel).strokeBorder(Palette.lineStrong)
                }
            }
        }
    }

    private var isOpaque: Bool { reducesTransparency || contrast == .increased }

    /// What the bubble shows under the prompt, so a change between them fades rather than jumps.
    private var contentPhase: Int {
        if bubble.notice != nil { 1 }
        else if model.failure != nil { 2 }
        else if model.isAnswering && model.answer.isEmpty { 3 }
        else if !model.answer.isEmpty { 4 }
        else { 0 }
    }

    /// A turn's prompt, as a small line above its answer; the interview's opening, with Bubo's instructions, as its title.
    @ViewBuilder private func turnPrompt(_ text: String) -> some View {
        if text == brainSetup.openingPrompt {
            Text("Configura il Secondo cervello")
                .font(Typography.body(size: 12))
                .foregroundStyle(Palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(verbatim: text)
                .font(Typography.body(size: 12))
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var prompt: some View {
        // At the bottom, beside the last line, once a long prompt wraps.
        HStack(alignment: .bottom, spacing: Spacing.xSmall) {
            // Wraps up to six lines, then scrolls; Invio sends.
            TextField("Chiedi a Bubo", text: $model.prompt, axis: .vertical)
                .lineLimit(1...6)
                .textFieldStyle(.plain)
                .font(Typography.body(size: 15))
                .focused($promptHasFocus)
                .onSubmit(model.ask)
                // On macOS the title is only a placeholder, so VoiceOver would find a nameless field.
                .accessibilityLabel("Chiedi a Bubo")
                .accessibilityIdentifier("bubble.prompt")
                // Before the prompt's keys, so ↑↓, Tab, Invio and Esc go to the menu while it shows.
                .slashCompletion(text: $model.prompt, folder: brainSetup.secondBrainFolder)
                .onKeyPress(phases: .down, action: promptKeyPress)
                // Esc closes and the answer goes on; ⌘. stops it, from the Ferma button.
                .onExitCommand(perform: bubble.close)
            if model.isAnswering {
                Button("Ferma", systemImage: "stop.fill", action: model.stop)
                    .keyboardShortcut(".", modifiers: .command)
                    .help("Ferma la risposta")
                    .transition(.opacity)
            }
            // The turns so far go; the next prompt asks without them.
            Button("Nuova Domanda", systemImage: "square.and.pencil", action: model.startNewQuestion)
                .keyboardShortcut("n", modifiers: .command)
                .help("Nuova Domanda (⌘N)")
                .accessibilityIdentifier("bubble.newQuestion")
            // The Domanda ↔ Sessione switch: the conversation so far goes with it, in the HUD. Not twice: with a
            // proposal above, that one already says where the Sessione goes.
            if model.sessionProposal == nil {
                Button("Trasforma in Sessione", systemImage: "arrow.triangle.branch") {
                    hud.turnIntoSession(model.turnIntoSession())
                }
                .help("Trasforma in Sessione")
            }
            // The same Domanda in the window, with its earlier turns and room for long answers (ADR 0013).
            Button("Apri nella finestra", systemImage: "arrow.up.left.and.arrow.down.right") {
                bubble.close()
                hud.show(question: model.currentQuestionID)
            }
            .help("Apri nella finestra")
            .accessibilityIdentifier("bubble.openHUD")
            Button("Chiudi", systemImage: "xmark", action: bubble.close)
                .help("Chiudi")
        }
        .animation(Motion.isReduced ? nil : Motion.quick, value: model.isAnswering)
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
        .foregroundStyle(Palette.textSecondary)
        .padding(Spacing.small)
        // A rectangle rather than a capsule, which would bulge around several lines.
        .background(Palette.surface, in: .rect(cornerRadius: CornerRadius.large))
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.large)
                .strokeBorder(promptHasFocus || isOpaque ? Palette.lineStrong : Palette.line)
        }
    }

    /// The prompt's keys: ⇧Invio a new line, and the chip's Tab, ⇧Tab, ⌥↑ and ⌥↓ as in the HUD; Esc keeps closing the
    /// bubble, so it never hands the chip back to the router here.
    private func promptKeyPress(_ press: KeyPress) -> KeyPress.Result {
        if press.key == .return, press.modifiers.contains(.shift) {
            // Through the field editor, so the line goes where the cursor is.
            NSApp.sendAction(#selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)), to: nil, from: nil)
            return .handled
        }
        guard !model.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              model.handleChipKey(press.key, modifiers: press.modifiers, escapeReturnsToRouter: false)
        else { return .ignored }
        return .handled
    }
}

/// The bubble on its way in or out: scaled toward the Orb's side, or past full size when it grows into the HUD.
private struct BubbleMotion: ViewModifier {
    let bubble: PanelBubble
    let isPresented: Bool

    func body(content: Content) -> some View {
        // Read as the bubble leaves, not when it came: it only then knows whether it goes into the HUD.
        let grows = bubble.appearance == .grow && !isPresented
        content
            .scaleEffect(grows ? (bubble.closesExpanding ? 1.06 : 0.9) : 1,
                         anchor: bubble.closesExpanding ? .center : bubble.side.anchor)
            .opacity(isPresented ? 1 : 0)
    }
}

#Preview {
    let bubble = PanelBubble()
    bubble.open(focus: .prompt)
    let model = QuestionModel()
    return PanelBubbleView(bubble: bubble, model: model, hud: HUDPresenter(),
                           brainSetup: SecondBrainConversation(questions: model, secondBrain: SecondBrain(index: nil)))
        .padding()
}
