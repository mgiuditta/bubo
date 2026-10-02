import SwiftUI

/// The model · sforzo of a Sessione's turns, in its menu: from the next turn, without restarting it (spec 10, Nella
/// Sessione). "Più forte" climbs one step of the Scala from the one chosen.
struct SessionModelMenu: View {
    /// The step chosen for the Sessione; `nil` for the model and effort set in `claude`.
    let model: Scala.Step?
    let setModel: (Scala.Step?) -> Void

    /// The steps offered: those below Fable, whose efforts the SDK lowers by itself where a model lacks them.
    private let scala = Scala(catalog: nil)

    var body: some View {
        Menu("Modello dal prossimo turno") {
            if let model, let stronger = scala.step(above: model) {
                Button("Più forte: \(stronger.name)") { setModel(stronger) }
                Divider()
            }
            item(Text("Predefinito di Claude"), for: nil)
            ForEach(scala.steps, id: \.self) { step in
                item(Text(verbatim: step.name), for: step)
            }
        }
    }

    /// The menu item that chooses `step`, with a check on the one chosen now.
    @ViewBuilder
    private func item(_ title: Text, for step: Scala.Step?) -> some View {
        Button {
            setModel(step)
        } label: {
            if step == model {
                Label { title } icon: { Image(systemName: "checkmark") }
            } else {
                title
            }
        }
    }
}

#Preview {
    SessionModelMenu(model: Scala.Step(family: .sonnet, effort: .medium)) { _ in }
        .padding()
        .background(Palette.ink)
}
