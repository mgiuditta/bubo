import SwiftUI

@main
struct BuboApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    /// The miniature Orb of the menu bar, drawn once.
    private let menuBarIcon = MenuBarOrb.makeImage()

    var body: some Scene {
        Window("Bubo", id: HUDPresenter.windowID) {
            HUDView(questions: appDelegate.questions, sessions: appDelegate.sessions)
                .environment(appDelegate.hud)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Nuova Sessione…") { appDelegate.hud.createSession() }
                    .keyboardShortcut("n")
                    .disabled(appDelegate.sessions == nil)
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
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 800)
        .defaultLaunchBehavior(.presented)

        Settings {
            SettingsView()
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
                Text(MenuBarOrb.accessibilityDescription)
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
