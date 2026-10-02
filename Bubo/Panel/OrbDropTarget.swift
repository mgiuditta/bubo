import AppKit
import os

/// What a drag onto the Orb of the Panel brings: files, folders, text, web addresses and images become Allegati
/// (spec 09, Trascinamento sull'Orb).
enum OrbDropTarget {
    /// The pasteboard types the Orb accepts.
    static let types: [NSPasteboard.PasteboardType] = [.fileURL, .URL, .png, .tiff, .string]

    /// Returns the Allegati of `pasteboard`, in the order they were dragged; empty when nothing can be attached.
    ///
    /// Files and folders go by path. An image with no file behind it, such as one dragged from a web page, is saved
    /// as a PNG in a new folder inside `imageDirectory`, where `claude` reads it; a web address and a text go as text.
    static func attachments(from pasteboard: NSPasteboard, imageDirectory: URL) -> [Allegato] {
        let files = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
            as? [URL] ?? []
        if !files.isEmpty { return files.map(Allegato.init(fileAt:)) }
        if pasteboard.availableType(from: [.png, .tiff]) != nil, let image = NSImage(pasteboard: pasteboard),
           let saved = save(image, in: imageDirectory) {
            return [Allegato(fileAt: saved)]
        }
        let addresses = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] ?? []
        if !addresses.isEmpty { return addresses.map(Allegato.init(address:)) }
        if let text = pasteboard.string(forType: .string),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return [Allegato(draggedText: text)]
        }
        return []
    }

    /// Saves `image` as a new PNG in `directory`; `nil` when it cannot be written.
    private static func save(_ image: NSImage, in directory: URL) -> URL? {
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else { return nil }
        // A folder of its own, so the chip shows a plain name and no image overwrites another.
        let folder = directory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let name = String(localized: "Immagine", comment: "File name of an image dragged onto the Orb, before .png")
        let url = folder.appending(path: name).appendingPathExtension("png")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try png.write(to: url)
            return url
        } catch {
            Logger.drop.error("Dragged image not saved: \(error)")
            return nil
        }
    }
}

private extension Logger {
    static let drop = Logger(subsystem: "com.mgiuditta.bubo", category: "drop")
}
