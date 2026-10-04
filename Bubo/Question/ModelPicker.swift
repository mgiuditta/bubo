import SwiftUI

/// The chip of the chat as a menu: Automatico (the router chooses), a Claude family or a model of the user's Copilot
/// plan. The pick holds for the whole chat; Tab, ⌥↑, ⌥↓ and Esc in the prompt still work.
struct ModelPicker: View {
    let model: QuestionModel

    var body: some View {
        Menu {
            Button("Automatico") { model.choose(nil) }
            Section(String("Claude")) {
                ForEach(model.claudeChoices, id: \.model) { route in
                    Button(route.family?.name ?? route.model ?? "") { model.choose(route) }
                }
            }
            if !model.copilotModels.isEmpty {
                Section(String("GitHub Copilot")) {
                    ForEach(model.copilotModels, id: \.id) { copilot in
                        Button(copilot.name) { model.choose(.copilot(copilot, effort: nil, reason: .chosenByUser)) }
                    }
                }
            }
        } label: {
            if let route = model.chipRoute {
                RouterChip(route: route)
            } else {
                RouterChip.automatic
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        // Only vertically: the reason truncates in a narrow place, like the Panel's bubble.
        .fixedSize(horizontal: false, vertical: true)
        // Reads the plan's models once; without a paid `copilot` the section stays out.
        .task { await model.readCopilotModels() }
        .accessibilityAction(named: "Modello successivo") { model.chooseModel(forward: true) }
        .accessibilityAction(named: "Sforzo più alto") { model.chooseEffort(stronger: true) }
        .accessibilityAction(named: "Sforzo più basso") { model.chooseEffort(stronger: false) }
        .accessibilityAction(named: "Torna al router") { model.returnToRouter() }
    }
}

extension QuestionModel {
    /// Handles the chip's keys in the prompt: Tab and ⇧Tab the model, ⌥↑ and ⌥↓ the effort and, when
    /// `escapeReturnsToRouter`, Esc back to the router; returns `false` for any other key, or one with nothing to
    /// change, which keeps its usual meaning.
    func handleChipKey(_ key: KeyEquivalent, modifiers: EventModifiers, escapeReturnsToRouter: Bool) -> Bool {
        switch key {
        case .tab:
            chooseModel(forward: !modifiers.contains(.shift))
            return true
        // AppKit delivers ⇧Tab as the back-tab character.
        case KeyEquivalent("\u{19}"):
            chooseModel(forward: false)
            return true
        case .upArrow where modifiers.contains(.option):
            return chooseEffort(stronger: true)
        case .downArrow where modifiers.contains(.option):
            return chooseEffort(stronger: false)
        case .escape where escapeReturnsToRouter:
            return returnToRouter()
        default:
            return false
        }
    }
}
