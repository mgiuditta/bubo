import SwiftUI

/// A file in the Galassia's list: its name, under it the folder it is in, the lines the Sessioni added and removed in
/// it, and the signs of the Sessioni that wrote it, with a double ring when more than one did.
struct GalaxyFileRow: View {
    /// The file's path from the Progetto.
    let path: String
    /// The Sessioni that wrote it, oldest first.
    var writers: [GalaxySession] = []
    /// The lines the Sessioni added and removed in it; `nil` when none changed it.
    var lineCounts: (added: Int, removed: Int)?

    var body: some View {
        let file = path as NSString
        let folder = file.deletingLastPathComponent
        HStack(spacing: Spacing.xxSmall) {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: file.lastPathComponent)
                    .font(Typography.body(size: 13))
                    .foregroundStyle(Palette.textPrimary)
                if !folder.isEmpty {
                    Text(verbatim: folder)
                        .font(Typography.mono(size: 10))
                        .foregroundStyle(Palette.textSecondary)
                        .truncationMode(.head)
                }
            }
            if !writers.isEmpty || lineCounts != nil {
                Spacer(minLength: 0)
            }
            if let lineCounts {
                Text(verbatim: "+\(lineCounts.added) −\(lineCounts.removed)")
                    .font(Typography.mono(size: 11))
                    .foregroundStyle(Palette.textSecondary)
                    .monospacedDigit()
            }
            if !writers.isEmpty {
                signs
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }

    private var signs: some View {
        let names = writers.map(\.title).formatted(.list(type: .and))
        let description = writers.count > 1
            ? Text("Modificato da più Sessioni: \(names)") : Text("Modificato da \(names)")
        return HStack(spacing: 2) {
            if writers.count > 1 {
                Image(systemName: "circle.circle")
            }
            Text(verbatim: writers.map(\.sign).joined(separator: " "))
        }
        .font(Typography.mono(size: 11))
        .foregroundStyle(Palette.textPrimary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(description)
        .help(description)
    }
}
