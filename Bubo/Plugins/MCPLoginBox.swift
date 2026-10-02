import AppKit
import SwiftUI

/// The action of an MCP server that waits for a login: Accedi, with the `claude mcp login` command beside it, and
/// Controlla; when the login fails, the command to copy (spec 20, `needs-auth`).
struct MCPLoginBox: View {
    let server: String
    /// The command for the Terminale.
    let command: String
    /// Runs `claude mcp login`; whether it succeeded.
    let logIn: () async throws -> Bool
    /// Reads the status again; `nil` where there is nothing to read it from.
    var check: (() async -> Void)?
    @State private var login: Task<Void, Never>?
    @State private var isChecking = false
    @State private var hasFailed = false
    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            HStack(spacing: Spacing.small) {
                if login == nil {
                    Button("Accedi", action: start)
                        .buttonStyle(.borderedProminent)
                        .accessibilityLabel(Text("Accedi a \(server)"))
                        .disabled(isChecking)
                } else {
                    Button("Annulla") { login?.cancel() }
                    LoadingLabel("Aspetto l'accesso nel browser…")
                }
                if let check, login == nil {
                    Button("Controlla") {
                        isChecking = true
                        Task {
                            await check()
                            isChecking = false
                        }
                    }
                    .disabled(isChecking)
                    if isChecking { LoadingLabel("Leggo lo stato…") }
                }
            }
            Text(verbatim: command)
                .font(.caption.monospaced())
                .foregroundStyle(Palette.textSecondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if hasFailed {
                VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                    Text("L'accesso non è riuscito. Esegui nel Terminale il comando qui sotto, poi premi Controlla.")
                        .foregroundStyle(Palette.danger)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(didCopy ? "Copiato" : "Copia il comando", action: copy)
                }
            }
        }
    }

    private func start() {
        hasFailed = false
        didCopy = false
        login = Task {
            defer { login = nil }
            do {
                hasFailed = try await !logIn()
            } catch {
                // Cancelled: nothing failed.
            }
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        didCopy = true
    }
}

#Preview {
    MCPLoginBox(server: "linear", command: "claude mcp login linear") { false } check: {}
        .padding()
}
