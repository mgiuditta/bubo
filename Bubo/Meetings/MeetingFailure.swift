import Foundation

/// Why a Riunione was not recorded or not saved: each case says what to do, never a silent error.
nonisolated enum MeetingFailure: Error, Equatable, Sendable {
    /// No Secondo cervello is chosen, so the note has nowhere to go.
    case noSecondBrain
    /// The user said no to the microphone.
    case microphoneDenied
    /// The microphone is missing or does not start.
    case microphoneUnavailable
    /// macOS refused the audio of the app: permission denied, or the tap could not start.
    case appAudioDenied
    /// The chosen app, named, has no audio for Core Audio yet.
    case appSilent(String)
    /// The main language of the Riunioni cannot be transcribed.
    case languageUnsupported
    /// The transcription stopped; the audio is kept.
    case transcriptionFailed
    /// The note could not be written; the audio is kept.
    case noteNotWritten
    /// An imported file cannot be read, or a video has no audio.
    case fileUnreadable
    /// The web link has no video that `yt-dlp` can download, or not in a format the Mac can read.
    case noVideo
    /// `yt-dlp` could not be downloaded, or its checksum did not match: nothing was run.
    case downloaderUnavailable

    /// What happened and what to do, for the window and VoiceOver.
    var explanation: LocalizedStringResource {
        switch self {
        case .noSecondBrain:
            "Per salvare la Riunione, scegli la cartella del Secondo cervello in Impostazioni › Generale."
        case .microphoneDenied:
            "Bubo non può usare il microfono. Consentilo in Impostazioni di Sistema › Privacy e sicurezza › Microfono."
        case .microphoneUnavailable:
            "Il microfono non risponde. Controlla che sia collegato e riprova."
        case .appAudioDenied:
            "Bubo non può sentire l'audio dell'app. Consentilo in Impostazioni di Sistema › Privacy e sicurezza › Registrazione schermo e audio di sistema."
        case let .appSilent(app):
            "\(app) non sta riproducendo audio. Entra nella chiamata e riprova."
        case .languageUnsupported:
            "Bubo non può trascrivere questa lingua. L'audio è salvato sul Mac. Scegli un'altra lingua delle Riunioni."
        case .transcriptionFailed:
            "Trascrizione non riuscita. L'audio è salvato sul Mac."
        case .noteNotWritten:
            "Cartella del Secondo cervello non trovata: la nota non è stata salvata. L'audio è salvato sul Mac. Controlla la cartella in Impostazioni › Generale."
        case .fileUnreadable:
            "Bubo non riesce a leggere il file o il video non ha audio."
        case .noVideo:
            "Questo link non ha un video che posso scaricare."
        case .downloaderUnavailable:
            "Non sono riuscito a scaricare yt-dlp"
        }
    }

    /// Whether the recording is over and its audio kept, so the note can be tried again from it.
    var keepsAudio: Bool {
        switch self {
        case .languageUnsupported, .transcriptionFailed, .noteNotWritten: true
        default: false
        }
    }

    /// The pane of System Settings that fixes it; `nil` when none does.
    var settingsURL: URL? {
        switch self {
        case .microphoneDenied: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        case .appAudioDenied: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")
        default: nil
        }
    }
}
