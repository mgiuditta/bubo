import SwiftUI

/// The window of a Riunione: the app to record and the consent first, then the recording, then where the note went.
struct MeetingView: View {
    let recorder: MeetingRecorder
    @State private var title = ""
    @State private var apps: [MeetingApp] = []
    @State private var app: MeetingApp?
    @State private var hasInformed = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            switch recorder.phase {
            case let .recording(recording):
                RecordingSection(recording: recording) {
                    Task { await recorder.stop() }
                }
            case .processing:
                Section {
                    LoadingLabel("Bubo trascrive e riassume la Riunione sul Mac…")
                }
            case .idle, .saved, .failed:
                outcome
                setup
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .task(id: recorder.isRecording) {
            guard !recorder.isRecording else { return }
            apps = MeetingApp.running()
            if app.map(apps.contains) != true { app = apps.first { MeetingApp.callApps.contains($0.bundleID) } }
            hasInformed = false
        }
    }

    /// How the last Riunione ended, when it did.
    @ViewBuilder private var outcome: some View {
        switch recorder.phase {
        case let .saved(file):
            Section {
                Label {
                    Text("Riunione salvata in \(file.lastPathComponent)")
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Palette.success)
                }
                Button("Apri la nota") { NSWorkspace.shared.open(file) }
            }
        case let .failed(failure):
            Section {
                Label {
                    Text(failure.explanation)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Palette.danger)
                }
                if let url = failure.settingsURL {
                    Button("Apri Impostazioni di Sistema") { openURL(url) }
                }
            }
        default:
            EmptyView()
        }
    }

    /// The title, the app and the consent, then Registra.
    private var setup: some View {
        Section {
            TextField("Titolo", text: $title, prompt: Text("Riunione"))
            Picker("Audio dei partecipanti", selection: $app) {
                Text("Nessuna app, solo il microfono").tag(MeetingApp?.none)
                ForEach(apps) { app in
                    Text(verbatim: app.name).tag(Optional(app))
                }
            }
            Toggle("Ho avvisato i partecipanti della registrazione", isOn: $hasInformed)
            Button("Registra") {
                Task { await recorder.start(titled: title, app: app) }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!hasInformed)
        } header: {
            Text("Registra una Riunione")
        } footer: {
            Text("Bubo registra il tuo microfono e l'audio dell'app scelta, senza bot nella chiamata. Trascrive sul Mac e nel Secondo cervello salva solo la nota, non l'audio.")
        }
    }
}

/// The Riunione being recorded: the red dot, the time and Ferma.
private struct RecordingSection: View {
    let recording: MeetingRecorder.Recording
    let stop: () -> Void

    var body: some View {
        Section {
            HStack {
                Image(systemName: "record.circle.fill")
                    .foregroundStyle(Palette.danger)
                    .accessibilityHidden(true)
                Text(verbatim: recording.title)
                Spacer()
                Text(timerInterval: recording.start...Date.distantFuture, countsDown: false)
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Registrazione in corso: \(recording.title)")
            if let app = recording.app {
                LabeledContent("Audio dei partecipanti") {
                    Text(verbatim: app.name)
                }
            }
            Button("Ferma e salva", action: stop)
                .keyboardShortcut(.defaultAction)
        }
    }
}
