import SwiftUI

extension View {
    /// Shows the `/` menu above this prompt field while `text` is `/` and a name without spaces (#689): ↑↓ choose,
    /// Tab or Invio complete to `/name `, Esc closes the menu. With the menu closed the keys do what they did.
    ///
    /// Apply it to the field itself, before the field's own `onKeyPress`, so its keys come first.
    ///
    /// - Parameters:
    ///   - folder: Where the prompt works, whose `.claude` skills join the user's and the plugins'.
    ///   - isShowing: Set while the menu shows, for a sheet to lift its Invio and Esc shortcuts, which come before it.
    func slashCompletion(text: Binding<String>, folder: URL?, isShowing: Binding<Bool> = .constant(false)) -> some View {
        modifier(SlashCompletion(text: text, folder: folder, isShowing: isShowing))
    }
}

/// The `/` menu of a prompt field: the skills of `SkillCatalog` that match what follows the `/`, inline above the
/// field so it grows the window it is in (the Bolla fits its panel to the content) and never takes the focus.
struct SlashCompletion: ViewModifier {
    /// The most skills the menu shows.
    nonisolated static let limit = 8

    @Binding var text: String
    let folder: URL?
    @Binding var isShowing: Bool
    @State private var catalog: [Skill] = []
    @State private var selection = 0
    /// The text the menu was closed on with Esc: it stays closed until the text changes.
    @State private var dismissedText: String?

    func body(content: Content) -> some View {
        let matches = isOpen ? Self.matches(for: Self.query(in: text) ?? "", in: catalog) : []
        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
            if !matches.isEmpty {
                SlashMenu(skills: matches, selection: matches[min(selection, matches.count - 1)].id) { skill in
                    text = Self.completion(for: skill)
                }
            }
            content
                .onKeyPress(phases: .down) { press in
                    handle(press, matches: matches)
                }
        }
        // Reloaded as the menu opens, so a skill just written shows up.
        .task(id: CatalogKey(folder: folder, isOpen: isOpen)) {
            catalog = await SkillCatalog.skills(in: folder)
        }
        .onChange(of: text) {
            selection = 0
            if text != dismissedText { dismissedText = nil }
        }
        .onChange(of: matches.count) { _, count in
            isShowing = count > 0
            guard count > 0 else { return }
            AccessibilityNotification.Announcement(String(localized: "\(count) skill")).post()
        }
    }

    private var isOpen: Bool {
        Self.query(in: text) != nil && dismissedText != text
    }

    private func handle(_ press: KeyPress, matches: [Skill]) -> KeyPress.Result {
        guard !matches.isEmpty, press.modifiers.isDisjoint(with: [.command, .option, .control, .shift]) else {
            return .ignored
        }
        switch press.key {
        case .upArrow:
            selection = (min(selection, matches.count - 1) + matches.count - 1) % matches.count
        case .downArrow:
            selection = (min(selection, matches.count - 1) + 1) % matches.count
        case .tab, .return:
            text = Self.completion(for: matches[min(selection, matches.count - 1)])
        case .escape:
            dismissedText = text
        default:
            return .ignored
        }
        return .handled
    }

    /// What follows the `/` at the start of `text`, while it has no spaces; `nil` when the menu has nothing to show.
    nonisolated static func query(in text: String) -> String? {
        guard text.hasPrefix("/") else { return nil }
        let query = text.dropFirst()
        guard !query.contains(where: \.isWhitespace) else { return nil }
        return String(query)
    }

    /// The skills whose name contains `query`, ignoring case, those starting with it first; at most `limit`.
    nonisolated static func matches(for query: String, in skills: [Skill]) -> [Skill] {
        guard !query.isEmpty else { return Array(skills.prefix(limit)) }
        let containing = skills.filter { $0.name.localizedCaseInsensitiveContains(query) }
        let starting = containing.filter { $0.name.lowercased().hasPrefix(query.lowercased()) }
        let others = containing.filter { !$0.name.lowercased().hasPrefix(query.lowercased()) }
        return Array((starting + others).prefix(limit))
    }

    /// The prompt once `skill` is picked: its name after the `/` and a space, ready for the request.
    nonisolated static func completion(for skill: Skill) -> String {
        "/\(skill.name) "
    }
}

/// When the catalog loads again: a new folder, or the menu opening.
private struct CatalogKey: Equatable {
    let folder: URL?
    let isOpen: Bool
}
