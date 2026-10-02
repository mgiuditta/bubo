import SwiftUI

/// What Apri shows of a line Ricordato or Richiamato: the memory file, the memories recalled, or what `cerca` found.
struct MemoryLineSheet: View {
    let line: MemoryLine
    @Environment(\.dismiss) private var dismiss
    @State private var contents: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            Text(verbatim: line.subject)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            if case let .remembered(write) = line.event {
                Text(verbatim: write.file)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if let contents {
                ScrollView {
                    Text(verbatim: contents)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                LoadingLabel("Leggo la memoria…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack {
                Spacer()
                Button("Chiudi") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(Spacing.medium)
        .frame(width: 520, height: 480)
        .task { contents = await MemoryLine.contents(of: line) }
    }
}
