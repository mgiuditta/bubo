import SwiftUI

@main
struct BuboApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    /// The miniature Orb of the menu bar, drawn once.
    private let menuBarIcon = MenuBarGlyph.makeImage()

    var body: some Scene {
        Window("Bubo", id: HUDPresenter.windowID) {
            HUDView(questions: appDelegate.questions, sessions: appDelegate.sessions,
                    onboarding: appDelegate.onboarding, launch: appDelegate.launch)
                .environment(appDelegate.hud)
                .environment(appDelegate.summarizer)
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
                Divider()
            }
        }

        // In the Finestra menu, with no shortcut (spec 19).
        Window("Agenti", id: AgentsWindow.windowID) {
            AgentsWindow(store: appDelegate.sessions)
        }
        .defaultLaunchBehavior(.suppressed)

        Settings {
            SettingsView()
                .environment(appDelegate.sessions)
                .environment(appDelegate.secondBrain)
                .environment(appDelegate.semanticSearch)
                .environment(appDelegate.hotKeys)
                .environment(appDelegate.panel)
        }

        MenuBarExtra {
            MenuBarContent()
                .environment(appDelegate.hud)
                .environment(appDelegate.hotKeys)
                .environment(appDelegate.panel)
        } label: {
            Label {
                Text(MenuBarGlyph.accessibilityDescription)
            } icon: {
                Image(nsImage: menuBarIcon)
            }
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
