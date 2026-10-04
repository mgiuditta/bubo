import SwiftUI

/// The window of a Riunione: the app to record and the consent first, then the recording, then where the note went.
struct MeetingView: View {
    let recorder: MeetingRecorder
    @State private var title = ""
    @State private var apps: [MeetingApp] = []
    @State private var app: MeetingApp?
    @State private var hasInformed = false
    @Environment(\.openURL) private var openURL
    @Environment(SecondBrain.self) private var secondBrain
    @State private var isSettingUp = false
    /// The speakers of the Riunione just saved that can take a name.
    @State private var speakers: [String] = []

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
            MeetingImportSection(importer: recorder.imports)
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .task(id: recorder.isRecording) {
            guard !recorder.isRecording else { return }
            apps = MeetingApp.running()
            if app.map(apps.contains) != true {
                app = CallService.preferredApp(among: apps, services: CallService.saved())
            }
            hasInformed = false
        }
        // The first Riunione is the first use of the Secondo cervello for many: without a folder the note has nowhere
        // to go, so the quick setup asks for it, then the questions about the Riunioni (#563). With a folder the
        // recording starts at once: each question has a default, and Impostazioni › Generale changes it later.
        .task { isSettingUp = secondBrain.location == nil }
        .sheet(isPresented: $isSettingUp) { SecondBrainSetupSheet() }
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
            .task(id: file) {
                speakers = MeetingSpeakers.named(in: (try? String(contentsOf: file, encoding: .utf8)) ?? "")
            }
            if !speakers.isEmpty {
                MeetingSpeakersSection(file: file, speakers: $speakers)
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
                if recorder.canRetry {
                    Button("Riprova") { Task { await recorder.retry() } }
                        .help("Trascrive e riassume di nuovo la Riunione dall'audio salvato sul Mac")
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
            // The note goes in the Secondo cervello: without its folder the recording could only fail at the end.
            if secondBrain.location == nil {
                LabeledContent("Prima scegli dove salvare le note.") {
                    Button("Scegli la cartella…") { isSettingUp = true }
                }
            }
            Button("Registra") {
                Task { await recorder.start(titled: title, app: app) }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!hasInformed || secondBrain.location == nil)
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

/// The import of recordings and trascrizioni: how far it is with Annulla, or how it ended.
private struct MeetingImportSection: View {
    let importer: MeetingImporter

    var body: some View {
        Section {
            if let progress = importer.progress {
                LoadingLabel("Importazione \(progress.done + 1) di \(progress.total): \(progress.fileName)")
                Button("Annulla", action: importer.cancel)
            } else {
                if let outcome = importer.outcome { OutcomeRows(outcome: outcome) }
                Button("Importa Riunioni…", action: importer.chooseFiles)
                Button("Trascrivi un video da un link…", action: importer.chooseVideoLink)
            }
        } header: {
            Text("Importa Riunioni")
        } footer: {
            Text("Bubo trascrive sul Mac audio e video (m4a, mp3, wav, mp4, mov) e ripulisce le trascrizioni (vtt, srt, txt). Puoi scegliere anche una cartella. Da un link (YouTube, Vimeo…) scarica solo l'audio, con yt-dlp.")
        }
    }
}

/// How the last import ended: the notes written, the files skipped and those not imported, with why.
private struct OutcomeRows: View {
    let outcome: MeetingImporter.Outcome

    var body: some View {
        LabeledContent("Riunioni importate", value: outcome.saved.count, format: .number)
        if outcome.duplicates > 0 {
            LabeledContent("Saltate perché già importate", value: outcome.duplicates, format: .number)
        }
        if outcome.isCancelled {
            Text("Importazione annullata.")
        }
        ForEach(outcome.failures) { failure in
            Label {
                if let fileName = failure.fileName {
                    Text("\(fileName): \(failure.reason.explanation)")
                } else {
                    Text(failure.reason.explanation)
                }
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Palette.danger)
            }
        }
        if outcome.saved.count == 1, let file = outcome.saved.first {
            Button("Apri la nota") { NSWorkspace.shared.open(file) }
        }
    }
}
