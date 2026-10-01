import SwiftUI

/// A file in the Galassia's list: its name, and under it the folder it is in.
struct GalaxyFileRow: View {
    /// The file's path from the Progetto.
    let path: String

    var body: some View {
        let file = path as NSString
        let folder = file.deletingLastPathComponent
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
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}
