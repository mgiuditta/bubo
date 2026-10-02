import SwiftUI

/// The bubble beside the Orb: the subtitles of the Sintesi parlata, the prompt, and the answer as it streams.
///
/// It shows the Domanda of the HUD, so there is one Domanda only; "Rifai con…" and the Sessione open in the HUD.
struct PanelBubbleView: View {
    let bubble: PanelBubble
    @Bindable var model: QuestionModel
    let hud: HUDPresenter
    /// Called with the content's size whenever it changes, to fit the window around it.
    var onResize: (CGSize) -> Void = { _ in }
    @FocusState private var promptHasFocus: Bool

    /// The bubble's width, in points; the height follows the content.
    static let width: CGFloat = 360

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

    private var transition: AnyTransition {
        switch bubble.appearance {
        case .grow: .scale(scale: 0.9, anchor: bubble.side.anchor).combined(with: .opacity)
        case .fade: .opacity
        }
    }

    private var content: some View {
        GlassEffectContainer {
            VStack(alignment: .leading, spacing: Spacing.small) {
                // The Sintesi parlata as subtitles, while Bubo says it; VoiceOver users hear the voice already.
                if let subtitle = model.subtitle {
                    Text(verbatim: subtitle)
                        .font(Typography.body(size: 15))
                        .foregroundStyle(Palette.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityHidden(true)
                }
                // What was dropped on the Orb, waiting for the Domanda about it.
                if !model.attachments.isEmpty {
                    AttachmentChips(attachments: model.attachments, remove: model.detach)
                }
                SessionProposalButton(model: model, hud: hud)
                prompt
                if let notice = bubble.notice {
                    ErrorNotice("Sessione non creata", remedy: "\(notice)", actionTitle: "Chiudi", action: bubble.close)
                } else if let failure = model.failure {
                    QuestionNotice(failure: failure, model: model, pickRetry: hud.show)
                } else if model.isAnswering && model.answer.isEmpty {
                    LoadingLabel("Chiedo a Claude…")
                } else if !model.answer.isEmpty {
                    QuestionAnswer(model: model, pickRetry: hud.show)
                }
            }
            .padding(Spacing.medium)
            .frame(width: Self.width, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: CornerRadius.panel))
        }
    }

    private var prompt: some View {
        HStack(spacing: Spacing.xSmall) {
            TextField("Chiedi qualcosa a Claude", text: $model.prompt)
                .textFieldStyle(.plain)
                .font(Typography.body(size: 15))
                .focused($promptHasFocus)
                .onSubmit(model.ask)
                // On macOS the title is only a placeholder, so VoiceOver would find a nameless field.
                .accessibilityLabel("Chiedi qualcosa a Claude")
                .accessibilityIdentifier("bubble.prompt")
                .onExitCommand(perform: bubble.close)
            if model.isAnswering {
                Button("Ferma", systemImage: "stop.fill", action: model.stop)
                    .help("Ferma la risposta")
            }
            // The Domanda ↔ Sessione switch: the conversation so far goes with it, in the HUD.
            Button("Trasforma in Sessione", systemImage: "arrow.triangle.branch") {
                hud.createSession(from: model.turnIntoSession())
            }
            .help("Trasforma in Sessione")
            Button("Chiudi", systemImage: "xmark", action: bubble.close)
                .help("Chiudi")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
        .foregroundStyle(Palette.textSecondary)
        .padding(Spacing.small)
        .background(Palette.surface, in: .capsule)
        .overlay {
            Capsule().strokeBorder(promptHasFocus ? Palette.lineStrong : Palette.line)
        }
    }
}

#Preview {
    let bubble = PanelBubble()
    bubble.open(focus: .prompt)
    return PanelBubbleView(bubble: bubble, model: QuestionModel(), hud: HUDPresenter())
        .padding()
}
