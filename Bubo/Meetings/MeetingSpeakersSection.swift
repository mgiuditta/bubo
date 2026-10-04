import SwiftUI

/// The names of the speakers of the Riunione just saved: a field for each «Parlante», then Salva i nomi (#574).
struct MeetingSpeakersSection: View {
    /// The note of the Riunione.
    let file: URL
    /// The speakers of the note that can take a name, read again after each save.
    @Binding var speakers: [String]
    @State private var names: [String] = []
    @State private var failure: String?

    var body: some View {
        Section {
            ForEach(Array(speakers.enumerated()), id: \.element) { index, speaker in
                if names.indices.contains(index) {
                    TextField(text: $names[index], prompt: Text("Nome")) {
                        Text(verbatim: speaker)
                    }
                    .accessibilityLabel("Nome di \(speaker)")
                    .onSubmit(save)
                }
            }
            if let failure {
                Text(failure)
                    .foregroundStyle(Palette.danger)
            }
            Button("Salva i nomi", action: save)
                .disabled(names.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty })
        } header: {
            Text("Chi ha parlato")
        } footer: {
            Text("I nomi entrano nella nota come link alle persone, anche fra i partecipanti. La nota non cambia nome.")
        }
        .onChange(of: speakers, initial: true) {
            names = Array(repeating: "", count: speakers.count)
        }
    }

    private func save() {
        do {
            for (speaker, name) in zip(speakers, names) where !name.trimmingCharacters(in: .whitespaces).isEmpty {
                try MeetingSpeakers.rename(speaker, to: name, inNoteAt: file)
            }
            failure = nil
            speakers = MeetingSpeakers.named(in: (try? String(contentsOf: file, encoding: .utf8)) ?? "")
            AccessibilityNotification.Announcement(String(localized: "Nomi salvati nella nota")).post()
        } catch {
            failure = String(localized: "Non è stato possibile salvare i nomi nella nota.")
        }
    }
}
