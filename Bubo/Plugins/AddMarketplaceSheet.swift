import SwiftUI

/// The Aggiungi marketplace sheet: `owner/repo`, a git URL or a folder on the Mac, registered Per me (spec 20).
///
/// A private repository uses the git credentials the user already has; Bubo never asks for any, and without them
/// `claude` fails at once with one line of explanation.
struct AddMarketplaceSheet: View {
    let catalog: PluginCatalog
    @Environment(\.dismiss) private var dismiss
    @State private var source = ""
    @State private var isChoosingFolder = false
    @State private var failure: Text?
    @State private var adding: Task<Void, Never>?

    /// The source as `claude` gets it: trimmed, with `~` for the home folder expanded.
    private var trimmedSource: String {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("~/") ? URL.homeDirectory.appending(path: String(trimmed.dropFirst(2))).path : trimmed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            Text("Aggiungi marketplace")
                .font(Typography.body(size: 15, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            HStack {
                TextField("Sorgente", text: $source, prompt: Text(verbatim: "owner/repo"))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Button("Scegli cartella…") { isChoosingFolder = true }
            }
            Text("Un repository GitHub (owner/repo), un URL git o una cartella sul Mac. Per i repository privati usa le credenziali git che hai già.")
                .font(Typography.body(size: 11))
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let failure {
                failure
                    .font(Typography.body(size: 12))
                    .foregroundStyle(Palette.danger)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if adding != nil {
                    LoadingLabel("Aggiungo…")
                }
                Spacer()
                Button("Annulla", role: .cancel) {
                    adding?.cancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Aggiungi", action: add)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedSource.isEmpty || adding != nil)
            }
        }
        .padding(Spacing.large)
        .frame(width: 460)
        .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
            if case let .success(folder) = result { source = folder.path }
        }
    }

    private func add() {
        let source = trimmedSource
        guard !source.isEmpty, adding == nil else { return }
        failure = nil
        adding = Task {
            defer { adding = nil }
            do {
                let result = try await catalog.perform(.addMarketplace(source: source, scope: .user))
                if result.succeeded {
                    dismiss()
                } else {
                    failure = Text(marketplaceFailure: result)
                }
            } catch is CancellationError {
                return
            } catch {
                failure = Text(marketplaceError: error)
            }
        }
    }
}
