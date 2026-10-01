import os
import SwiftUI

/// Collega Linear and Scollega Linear: Bubo's custom script in `~/.linear/coding-tools.json`, written only after the
/// user has seen the line (spec 16). No token, no login: Linear runs the script, Bubo makes a Bozza.
struct LinearSettingsSection: View {
    var tools = LinearCodingTools()
    /// Whether the file runs Bubo; `nil` until read.
    @State private var isConnected: Bool?
    /// The user's script that Collega would replace, shown in the confirmation.
    @State private var otherScript: String?
    @State private var isConfirming = false
    @State private var failure: String?

    var body: some View {
        Section {
            Text(isConnected == true ? "Linear apre le issue in Bubo." : "Linear non è collegato.")
            if isConnected == true {
                Button("Scollega Linear", action: disconnect)
            } else {
                Button("Collega Linear…", action: confirm)
            }
            if let failure {
                Text(failure)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        } header: {
            Text(verbatim: "Linear")
        } footer: {
            Text("Da Linear, Work on issue › Custom script crea una Bozza in Bubo. Prima attiva Custom script in Linear: Settings › Code & reviews › Configure coding tools.")
        }
        .sheet(isPresented: $isConfirming) { confirmation }
        .task { refresh() }
    }

    private var confirmation: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            Text("Collegare Linear?")
                .font(.headline)
            Text("Bubo scrive questa voce in \(tools.file.path). Le altre voci del file restano com'erano.")
            script(tools.scriptText)
            if let otherScript {
                Text("Linear ha già uno script personalizzato: Bubo lo sostituisce e lo rimette com'era quando scolleghi Linear.")
                script(otherScript)
            }
            HStack {
                Spacer()
                Button("Annulla", role: .cancel) { isConfirming = false }
                    .keyboardShortcut(.cancelAction)
                Button("Collega", action: connect)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spacing.medium)
        .frame(width: 480)
    }

    private func script(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(.callout, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.small)
            .background(.quaternary, in: .rect(cornerRadius: 6))
    }

    /// Reads the file, then shows the confirmation; a file that is not valid JSON shows why instead.
    private func confirm() {
        do {
            otherScript = try tools.otherScriptText()
            failure = nil
            isConfirming = true
        } catch {
            failure = error.localizedDescription
        }
    }

    private func connect() {
        isConfirming = false
        change(tools.connect)
    }

    private func disconnect() {
        change(tools.disconnect)
    }

    private func change(_ change: () throws -> Void) {
        do {
            try change()
            failure = nil
        } catch {
            Logger.sessions.error("coding-tools.json not changed: \(String(describing: error), privacy: .private)")
            failure = error.localizedDescription
        }
        refresh()
    }

    private func refresh() {
        do {
            isConnected = try tools.isConnected()
        } catch {
            isConnected = nil
            failure = error.localizedDescription
        }
    }
}
