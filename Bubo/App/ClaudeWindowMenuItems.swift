import SwiftUI

/// Agenti and Plugin in the Finestra menu, and so in the Palette: only with `claude`, the one engine that has them
/// (#729).
struct ClaudeWindowMenuItems: View {
    let questions: QuestionModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if !questions.isClaudeMissing {
            Button("Agenti") { openWindow(id: AgentsWindow.windowID) }
            Button("Plugin") { openWindow(id: PluginsWindow.windowID) }
        }
    }
}
