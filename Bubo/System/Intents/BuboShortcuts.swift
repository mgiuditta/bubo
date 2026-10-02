import AppIntents

/// The App Shortcuts of Bubo, for Spotlight, Siri and Comandi rapidi; their phrases carry no data of the user.
struct BuboShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AskBuboIntent(),
                    phrases: ["Chiedi a \(.applicationName)", "Fai una domanda a \(.applicationName)"],
                    shortTitle: "Chiedi a Bubo",
                    systemImageName: "questionmark.bubble")
        AppShortcut(intent: NewSessionIntent(),
                    phrases: ["Nuova Sessione in \(.applicationName)", "Avvia una Sessione in \(.applicationName)"],
                    shortTitle: "Nuova Sessione",
                    systemImageName: "arrow.triangle.branch")
        AppShortcut(intent: OpenGalaxyIntent(),
                    phrases: ["Apri la Galassia di \(.applicationName)", "Mostra la Galassia in \(.applicationName)"],
                    shortTitle: "Apri Galassia",
                    systemImageName: "sparkles")
    }
}
