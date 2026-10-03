import SwiftUI

@main
struct BuboApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Bubo", id: HUDPresenter.windowID) {
            HUDView(questions: appDelegate.questions, sessions: appDelegate.sessions,
                    onboarding: appDelegate.onboarding, launch: appDelegate.launch)
                .environment(appDelegate.hud)
                .environment(appDelegate.summarizer)
                .environment(appDelegate.pushToTalk)
                .environment(appDelegate.hotKeys)
                .environment(appDelegate.deliveries)
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("Informazioni su Bubo", action: appDelegate.showAboutPanel)
            }
            CommandGroup(replacing: .newItem) {
                Button("Nuova Sessione…") { appDelegate.hud.createSession() }
                    .keyboardShortcut("n")
                    .disabled(appDelegate.sessions == nil)
                Button("Nuova Bozza…") { appDelegate.hud.createDraft() }
                    .keyboardShortcut("n", modifiers: [.option, .command])
                    .disabled(appDelegate.sessions == nil)
                Button("Sessione da issue GitHub…") { appDelegate.hud.pickIssue() }
                    .keyboardShortcut("i")
                    .disabled(appDelegate.sessions == nil)
                Divider()
                // Each names its Sessione, as the Palette has no other context; no shortcut (spec 16).
                if let session = appDelegate.sessions?.pullRequestSessionToOpen {
                    Button("Apri PR di «\(session.title)»…") { appDelegate.hud.openPullRequest(of: session) }
                        .disabled(GitHubCLI().executable == nil)
                } else {
                    Button("Apri PR…") {}
                        .disabled(true)
                }
                if let session = appDelegate.sessions?.pullRequestSessionToUpdate {
                    Button("Aggiorna la PR di «\(session.title)»") {
                        Task { await appDelegate.sessions?.requestPullRequestUpdate(of: session.id) }
                    }
                } else {
                    Button("Aggiorna PR") {}
                        .disabled(true)
                }
                // Off while the Sessione is in Lavora (spec 24); absent in a build without the Consegne.
                if ReleaseArea.deliveries.isAvailable() {
                    if let session = appDelegate.sessions?.deliverySessionToOpen {
                        Button("Consegna «\(session.title)»…") { appDelegate.hud.deliver(session) }
                            .disabled(session.activity == .lavora)
                    } else {
                        Button("Consegna…") {}
                            .disabled(true)
                    }
                }
                Divider()
                // In the File menu so the Palette lists it too; no shortcut.
                MeetingMenuItems(recorder: appDelegate.meetings)
                Divider()
                // Only with Bubo in front: no global shortcut (spec 14).
                Button("Cerca…") { appDelegate.togglePalette() }
                    .keyboardShortcut("k")
            }
            CommandGroup(before: .toolbar) {
                Section("Vista delle Sessioni") {
                    ForEach(VistaDelleSessioni.allCases) { vista in
                        Toggle(isOn: Binding {
                            appDelegate.hud.vista == vista
                        } set: { isOn in
                            if isOn { appDelegate.hud.switchVista(to: vista) }
                        }) {
                            Text(vista.title)
                        }
                        .keyboardShortcut(KeyEquivalent(vista.shortcut))
                    }
                }
                Divider()
                Button {
                    appDelegate.toggleTerminal()
                } label: {
                    appDelegate.sessions?.terminals.isShown == true ? Text("Nascondi il terminale")
                        : Text("Mostra il terminale")
                }
                .keyboardShortcut("`", modifiers: .control)
                .disabled(appDelegate.sessions?.terminals.isShown != true && appDelegate.sessions?.terminalSession == nil)
                Button {
                    appDelegate.togglePreview()
                } label: {
                    appDelegate.sessions?.previews.isShown == true ? Text("Nascondi l'anteprima")
                        : Text("Mostra l'anteprima")
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(appDelegate.sessions?.previews.isShown != true && appDelegate.sessions?.previewSession == nil)
                // ⌥⌘G, not ⇧⌘G: that is Trova precedente in the HIG (preflight #119).
                Button("Mostra la Galassia") { appDelegate.showGalaxy() }
                    .keyboardShortcut("g", modifiers: [.option, .command])
                Divider()
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 800)
        .defaultLaunchBehavior(.presented)

        // In the Finestra menu, with no shortcut (spec 14).
        .commands {
            CommandGroup(before: .windowList) {
                Button("Cronologia") { appDelegate.history.show() }
                // Also in the Palette, as every menu item; no shortcut (spec 18).
                Button("Costi") { appDelegate.costs.show() }
                Divider()
            }
        }

        // In the Finestra menu, with no shortcut (spec 19).
        Window("Agenti", id: AgentsWindow.windowID) {
            AgentsWindow(store: appDelegate.sessions)
        }
        .defaultLaunchBehavior(.suppressed)

        // In the Finestra menu and the Palette, with no shortcut (spec 20).
        Window("Plugin", id: PluginsWindow.windowID) {
            PluginsWindow(store: appDelegate.sessions)
        }
        .defaultLaunchBehavior(.suppressed)

        // In the Finestra menu, with no shortcut (spec 19).
        Window("Automazioni", id: AutomationsWindow.windowID) {
            AutomationsWindow(store: appDelegate.sessions, runner: appDelegate.executions) { id in
                appDelegate.hud.show(session: id)
            }
        }
        .defaultLaunchBehavior(.suppressed)

        Settings {
            SettingsView()
                .environment(appDelegate.sessions)
                .environment(appDelegate.secondBrain)
                .environment(appDelegate.semanticSearch)
                .environment(appDelegate.hotKeys)
                .environment(appDelegate.panel)
                .environment(appDelegate.remote)
                .environment(appDelegate.macOnlyProjects)
                .environment(appDelegate.ledger)
                .environment(appDelegate.deliveries)
                // System controls, as macOS expects of the Impostazioni, but only dark like the rest of Bubo
                // (design system, ADR 0004).
                .preferredColorScheme(.dark)
        }

        MenuBarExtra {
            MenuBarContent(sessions: appDelegate.sessions, questions: appDelegate.questions, meetings: appDelegate.meetings)
                .environment(appDelegate.hud)
                .environment(appDelegate.hotKeys)
                .environment(appDelegate.panel)
        } label: {
            MenuBarLabel(sessions: appDelegate.sessions)
        }

        // Only while a Riunione is recorded: the indicator always in sight (#545).
        MenuBarExtra(isInserted: Binding { appDelegate.meetings.isRecording } set: { _ in }) {
            MeetingMenuItems(recorder: appDelegate.meetings)
            Button("Mostra la Riunione") { appDelegate.meetingWindow.show() }
        } label: {
            MeetingIndicator()
        }

        #if DEBUG
        Window("Debug Orb", id: OrbDebugView.windowID) {
            OrbDebugView(controls: .shared)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
        #endif
    }
}
