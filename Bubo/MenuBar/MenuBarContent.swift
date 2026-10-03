import SwiftUI

/// The menu of Bubo's menu bar item: the Sessioni that wait for the user, the Quota, then the commands.
///
/// The Quota is the last one saved: opening the menu never starts a `claude`.
struct MenuBarContent: View {
    /// The Sessioni; `nil` when they cannot be kept.
    let sessions: SessionStore?
    /// The Domanda's model, which keeps the latest Quota.
    let questions: QuestionModel
    /// The Riunioni.
    let meetings: MeetingRecorder
    @Environment(HUDPresenter.self) private var hud
    @Environment(HotKeyCenter.self) private var hotKeys
    @Environment(OrbPanelController.self) private var panel
    @Environment(DocumentImporter.self) private var documents
    @Environment(\.openWindow) private var openWindow
    /// The Debug switch that shows the 1.1 areas off, as in a Release build.
    @AppStorage(ReleaseArea.hidesUnreleasedKey) private var hidesUnreleased = false

    var body: some View {
        @Bindable var panel = panel
        let waiting = Self.waitingSessions(in: sessions?.sessions ?? [])
        if !waiting.isEmpty {
            // As the Board's column: Attende te gathers the Errore too.
            Section {
                ForEach(waiting) { session in
                    Button {
                        hud.show(session: session.id)
                    } label: {
                        Image(nsImage: session.activity == .attende ? Self.waitingDot : Self.errorDot)
                            .accessibilityHidden(true)
                        Text(session.title)
                        Text(session.activity.title)
                    }
                }
            } header: {
                Text(BoardColumn.attendeTe.title)
            }
        }
        let quota = questions.quota
        let now = Date.now
        if [quota.fiveHour, quota.sevenDay].contains(where: { ($0?.resetsAt ?? .distantPast) > now }) {
            Section("Quota") {
                if let window = quota.fiveHour, window.resetsAt > now {
                    Text("5 ore: \(window.used, format: .percent.precision(.fractionLength(0))) · si azzera alle \(window.resetsAt, format: .dateTime.hour().minute())")
                }
                if let window = quota.sevenDay, window.resetsAt > now {
                    Text("Settimana: \(window.used, format: .percent.precision(.fractionLength(0))) · si azzera \(window.resetsAt, format: .dateTime.weekday(.abbreviated)) alle \(window.resetsAt, format: .dateTime.hour().minute())")
                }
            }
        }
        Divider()
        Button("Nuova Sessione…") { hud.createSession() }
            .disabled(sessions == nil)
        MeetingMenuItems(recorder: meetings)
        Button("Importa nel Secondo cervello…", action: documents.chooseAndImport)
            .disabled(!documents.canImport)
        Button("Mostra HUD  \(hotKeys.shortcut.displayName)") { hud.show() }
        Toggle("Mostra Panel", isOn: $panel.isShown)
        Toggle("Panel ridotto", isOn: $panel.isReduced)
            .disabled(!panel.isShown)
        Button("Chiedi nel Panel", action: panel.askInPanel)
            .disabled(!panel.isShown)
        #if DEBUG
        Button("Debug Orb…") { openWindow(id: OrbDebugView.windowID) }
        Toggle("Aree 1.1 spente", isOn: $hidesUnreleased)
        #endif
        Divider()
        SettingsLink {
            Text("Impostazioni…")
        }
        .keyboardShortcut(",")
        Divider()
        Button("Esci da Bubo") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    /// The open Sessioni that wait for the user, as the menu lists them: Attende te first, the longest wait on top,
    /// then Errore.
    static func waitingSessions(in sessions: [Session]) -> [Session] {
        Session.inActivityOrder(sessions.filter { $0.isLive && ($0.activity == .attende || $0.activity == .errore) })
    }

    /// The dot of a Sessione in Attende te: Lume, the one signal (ADR 0004).
    private static let waitingDot = makeDot(Palette.attention)
    /// The dot of a Sessione in Errore.
    private static let errorDot = makeDot(Palette.danger)

    /// Creates a dot in `color`, not a template, so the menu keeps its colour.
    private static func makeDot(_ color: Color) -> NSImage {
        let image = NSImage(size: CGSize(width: 8, height: 8), flipped: false) { bounds in
            NSColor(color).setFill()
            NSBezierPath(ovalIn: bounds).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}
