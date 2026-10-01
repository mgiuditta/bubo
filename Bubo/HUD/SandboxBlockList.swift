import SwiftUI

/// The latest blocks of the Sandbox in a Sessione, newest last, a few at a time.
struct SandboxBlockList: View {
    /// The blocks, oldest first.
    let blocks: [SandboxBlock]
    /// The Sessione's Progetto, whose Sandbox Consenti widens.
    let project: URL
    let sandbox: SandboxStore

    /// The most blocks shown; the others are counted.
    static let shownLimit = 3

    var body: some View {
        let allowances = sandbox.allowances(in: project)
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            ForEach(blocks.suffix(Self.shownLimit), id: \.self) { block in
                SandboxBlockRow(block: block, isAllowed: block.allowance.map(allowances.contains) == true) {
                    if let allowance = block.allowance { sandbox.allow(allowance, in: project) }
                }
            }
            if blocks.count > Self.shownLimit {
                Text("Altri blocchi in questo turno: \(blocks.count - Self.shownLimit)")
                    .font(Typography.body(size: 11))
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Blocchi della Sandbox")
    }
}
