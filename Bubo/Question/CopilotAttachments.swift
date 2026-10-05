import Foundation
import UniformTypeIdentifiers

/// The Allegati of a Domanda as Copilot reads them (#725, ADR 0014).
///
/// `copilot` reads a text file, an image or a folder from its path, as `attachments` of the Copilot SDK; a text with
/// no file behind it, and the text Bubo extracted from a PDF, go in the prompt under their name. Any other file has
/// nothing Copilot can read: it is ``unreadable``, and the Domanda does not leave without it.
nonisolated struct CopilotAttachments: Equatable, Sendable {
    /// An Allegato `copilot` reads from its path.
    struct Attachment: Equatable, Sendable {
        /// How `copilot` reads it.
        enum Kind: String, Sendable {
            case file, image, folder
        }

        let kind: Kind
        let path: URL
        /// The name shown in its chip.
        let name: String

        /// The attachment as the bridge reads it.
        var jsonObject: [String: Any] {
            ["kind": kind.rawValue, "path": path.path(percentEncoded: false), "name": name]
        }
    }

    /// The Allegati `copilot` reads from the disk.
    private(set) var attachments: [Attachment] = []
    /// The Allegati whose text goes in the prompt.
    private(set) var inline: [Allegato] = []
    /// The Allegati Copilot cannot read: a file that is neither text nor an image, with no text Bubo could extract.
    private(set) var unreadable: [Allegato] = []

    /// Sorts `allegati` by how Copilot reads them.
    init(_ allegati: [Allegato]) {
        for allegato in allegati {
            guard let path = allegato.path else {
                inline.append(allegato)
                continue
            }
            switch allegato.kind {
            case .folder: attachments.append(Attachment(kind: .folder, path: path, name: allegato.name))
            case .image: attachments.append(Attachment(kind: .image, path: path, name: allegato.name))
            case .file, .text:
                if Self.isText(path) {
                    attachments.append(Attachment(kind: .file, path: path, name: allegato.name))
                } else if allegato.text != nil {
                    inline.append(allegato)
                } else {
                    unreadable.append(allegato)
                }
            }
        }
    }

    /// What Copilot reads of `question`: the question, then the text of each Allegato in the prompt under its name.
    ///
    /// Names are anyone's text, from Comandi rapidi too: their control and separator characters are escaped, so none
    /// of them adds a line that passes for the user's request.
    func prompt(_ question: String) -> String {
        guard !inline.isEmpty else { return question }
        let texts = inline.map { "--- \(RepoActivations.escaped($0.name)) ---\n\($0.text ?? "")" }
        return ([question] + texts).joined(separator: "\n\n")
    }

    /// Whether the file at `path` is text, which `copilot` reads as it is: source code and Markdown too.
    private static func isText(_ path: URL) -> Bool {
        let type = (try? path.resourceValues(forKeys: [.contentTypeKey]).contentType)
            ?? UTType(filenameExtension: path.pathExtension)
        return type?.conforms(to: .text) == true
    }
}
