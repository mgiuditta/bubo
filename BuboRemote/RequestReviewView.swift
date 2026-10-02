import RemoteKit
import SwiftUI

/// The full-screen page of a Richiesta that needs a careful read: levels 4–5, a long command, one outside the
/// Sandbox (spec 21). The whole command, never cut; only No and Consenti solo ora, each with Face ID.
struct RequestReviewView: View {
    let waiting: WaitingRequest
    let decide: (WaitingRequest, Verdict.Answer) async -> Void
    let close: () -> Void
    @State private var isDeciding = false

    private var request: RemoteRequest { waiting.request }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    RequestSummary(waiting: waiting, showsMac: true)
                    if let subject = request.subject {
                        Text(verbatim: subject)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(.fill.tertiary, in: .rect(cornerRadius: 12))
                    }
                    LabeledContent("Strumento") { Text(verbatim: request.tool) }
                    RequestDeadline(request: request)
                    Text("Sempre in questo Progetto: solo dal Mac.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button("No", role: .destructive) { answer(.deny) }
                        .buttonStyle(.bordered)
                    Button("Consenti solo ora") { answer(.allowOnce) }
                        .buttonStyle(.borderedProminent)
                }
                .controlSize(.large)
                .disabled(isDeciding)
                .padding()
            }
            .navigationTitle(Text("Livello \(request.level)"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi", action: close)
                }
            }
        }
    }

    private func answer(_ answer: Verdict.Answer) {
        Task {
            isDeciding = true
            await decide(waiting, answer)
            isDeciding = false
        }
    }
}
