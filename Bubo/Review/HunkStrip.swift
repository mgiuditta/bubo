import SwiftUI

/// The row of every blocco under Focus, a square each: accepted, rejected, undecided; the current one ringed.
/// A click goes to the blocco.
struct HunkStrip: View {
    let ids: [String]
    let decisions: [String: HunkDecision]
    /// The blocco the keyboard acts on.
    let current: String?
    let select: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 10, maximum: 10), spacing: Spacing.xxSmall)],
                  spacing: Spacing.xxSmall) {
            ForEach(ids, id: \.self) { id in
                RoundedRectangle(cornerRadius: 3)
                    .fill(ReviewFileList.color(of: decisions[id]))
                    .frame(width: 10, height: 10)
                    .overlay {
                        if id == current {
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(Palette.accentStrong)
                                .padding(-3)
                        }
                    }
                    .contentShape(.rect)
                    .onTapGesture { select(id) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Blocchi")
        .accessibilityValue(Text("Blocco \(position) di \(ids.count), \(ids.count { decisions[$0] != nil }) decisi"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: move(by: 1)
            case .decrement: move(by: -1)
            @unknown default: break
            }
        }
    }

    /// The current blocco's place, from 1.
    private var position: Int {
        (current.flatMap(ids.firstIndex(of:)) ?? 0) + 1
    }

    private func move(by offset: Int) {
        guard !ids.isEmpty else { return }
        select(ids[min(max(position - 1 + offset, 0), ids.count - 1)])
    }
}
