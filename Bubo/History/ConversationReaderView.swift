import AppKit
import SwiftUI

/// The right column of the Cronologia window: the conversation read only, on the message found and highlighted.
struct ConversationReaderView: View {
    @Bindable var reader: ConversationReader
    /// Riprendi and Continua da qui; `nil` offers neither.
    var actions: ResumeActions?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            header
            notices
            switch reader.content {
            case .loading:
                LoadingLabel("Leggo la conversazione…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed:
                ErrorNotice("Non riesco a leggere la conversazione",
                            remedy: "Controlla che la CLI claude funzioni nel Terminale, poi riprova.",
                            actionTitle: "Riprova") { Task { await reader.load() } }
                Spacer()
            case .available, .unavailable:
                messages
            }
        }
        .padding(Spacing.medium)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: ObjectIdentifier(reader)) { await reader.load() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
            VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                Text(verbatim: reader.result.title)
                    .font(Typography.body(size: 15, weight: .semibold))
                    .lineLimit(2)
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: details)
                    .font(Typography.mono(size: 10, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer(minLength: Spacing.small)
            let matches = reader.matches
            if matches.count > 1 {
                let position = (reader.current.flatMap(matches.firstIndex(of:)) ?? 0) + 1
                Text("\(position) di \(matches.count)")
                    .font(Typography.mono(size: 11, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
                    .accessibilityLabel(Text("Punto \(position) di \(matches.count)"))
            }
            Button("Punto successivo", systemImage: "chevron.down") { reader.showNextMatch() }
                .keyboardShortcut("g")
                .disabled(matches.isEmpty)
                .help(Text("Vai al punto successivo (⌘G)"))
            if let actions {
                // Gone from both sources, or not read yet: nothing to resume.
                let isAvailable = reader.content == .available
                Button("Riprendi", systemImage: "arrow.uturn.forward") { actions.resume(reader.result) }
                    .keyboardShortcut(.return, modifiers: .option)
                    .disabled(!isAvailable || !actions.canResume(reader.result))
                    .help(Text("Riprendi la conversazione (⌥↩)"))
                Button("Continua da qui", systemImage: "arrow.branch") {
                    actions.continueFrom(reader.result, upTo: reader.currentMessage)
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!isAvailable || reader.currentMessage == nil)
                .help(Text("Nuova Sessione con la conversazione fino al messaggio evidenziato (⌘↩)"))
            }
        }
    }

    @ViewBuilder
    private var notices: some View {
        if reader.content == .unavailable {
            notice("Conversazione non più disponibile: non si può riprendere.",
                   detail: "Restano solo i frammenti salvati nell'Indice.", systemImage: "exclamationmark.triangle")
        } else if reader.isPastCLIRetention(at: .now) {
            notice("Più vecchia di 30 giorni",
                   detail: "Si riprende dalla copia di Bubo, ma le modifiche ai file non si possono riavvolgere.",
                   systemImage: "clock.arrow.circlepath")
        }
        if reader.content != .unavailable, let command = reader.resumeCommand {
            HStack(spacing: Spacing.xSmall) {
                Text("Per riprenderla dal Terminale:")
                    .foregroundStyle(Palette.textSecondary)
                Text(verbatim: command)
                    .font(Typography.mono(size: 11))
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button("Copia il comando", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help(Text("Copia il comando"))
            }
            .font(Typography.body(size: 12))
        }
    }

    private func notice(_ text: LocalizedStringKey, detail: LocalizedStringKey?, systemImage: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xSmall) {
            Image(systemName: systemImage)
                .foregroundStyle(Palette.textSecondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                Text(text)
                    .font(Typography.body(size: 12, weight: .semibold))
                if let detail {
                    Text(detail)
                        .font(Typography.body(size: 12))
                        .foregroundStyle(Palette.textSecondary)
                }
            }
        }
        .padding(Spacing.xSmall)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: .rect(cornerRadius: CornerRadius.small))
        .accessibilityElement(children: .combine)
    }

    private var messages: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.small) {
                ForEach(reader.lines) { line in
                    TranscriptLineView(line: line, words: reader.words, isCurrent: line.id == reader.current,
                                       continueFromHere: continueFromHere(line))
                }
            }
            .scrollTargetLayout()
        }
        // Set without animation: the reader jumps to the message, with or without Riduci movimento.
        .scrollPosition(id: $reader.position, anchor: .center)
    }

    /// Continua da qui on `line`: only with a message id, in a conversation that can still be resumed.
    private func continueFromHere(_ line: TranscriptLine) -> (() -> Void)? {
        guard let actions, reader.content == .available, let message = line.message.id else { return nil }
        return { [result = reader.result] in actions.continueFrom(result, upTo: message) }
    }

    /// Fonte · Progetto · when.
    private var details: String {
        [reader.result.source == .session ? String(localized: "Sessione") : String(localized: "Cronologia CLI"),
         reader.result.project?.lastPathComponent,
         reader.result.date.formatted(date: .abbreviated, time: .shortened)]
            .compactMap(\.self).joined(separator: " · ")
    }
}
