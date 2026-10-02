import AppKit

/// The Condividi of macOS for one `.bubo` (spec 24, Mittente): it deletes the temporary folder of the file as soon
/// as the Condividi closes, whether the file went out, failed, or the user chose nothing.
final class DeliveryShare: NSObject, NSSharingServicePickerDelegate, NSSharingServiceDelegate {
    /// How the Condividi closed.
    enum Outcome: Equatable {
        /// Sent through the service with this title, such as AirDrop or Messaggi.
        case shared(channel: String)
        /// The service could not send it.
        case failed
        /// The user closed the Condividi without choosing a service.
        case cancelled
    }

    /// The `.bubo` to share.
    let file: URL
    /// The folder deleted at the end: the file's own temporary folder.
    let folder: URL
    private let finished: (Outcome) -> Void
    private var isFinished = false

    /// Creates the share of `file`, whose folder `folder` goes when the Condividi closes and `finished` is called.
    init(file: URL, folder: URL, finished: @escaping (Outcome) -> Void) {
        self.file = file
        self.folder = folder
        self.finished = finished
    }

    /// Shows the Condividi next to `view`.
    func show(relativeTo view: NSView) {
        let picker = NSSharingServicePicker(items: [file])
        picker.delegate = self
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    /// Deletes the folder once and tells how the Condividi closed.
    func finish(_ outcome: Outcome) {
        guard !isFinished else { return }
        isFinished = true
        try? FileManager.default.removeItem(at: folder)
        finished(outcome)
    }

    // MARK: NSSharingServicePickerDelegate

    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, delegateFor sharingService: NSSharingService)
        -> (any NSSharingServiceDelegate)? {
        self
    }

    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        if service == nil { finish(.cancelled) }
    }

    // MARK: NSSharingServiceDelegate

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        finish(.shared(channel: sharingService.title))
    }

    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: any Error) {
        finish(.failed)
    }
}
