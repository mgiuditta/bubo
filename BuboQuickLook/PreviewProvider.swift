import Foundation
import QuickLookUI
import UniformTypeIdentifiers

/// The Quick Look preview of a `.bubo` file (spec 24): the header in the clear and the Biglietti received, never the
/// encrypted content. Runs in its sandbox and reads the Biglietti from the App Group it shares with Bubo.
nonisolated final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    /// The size Quick Look gives the page.
    private static let pageSize = CGSize(width: 460, height: 230)

    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let store = TicketStore.standard
        let summary = try BuboFileSummary(contentsOf: request.fileURL, tickets: (try? store.tickets()) ?? [],
                                          ownKey: store.ownKeyID())
        let page = Data(PreviewPage(summary: summary).html.utf8)
        return QLPreviewReply(dataOfContentType: .html, contentSize: Self.pageSize) { _ in page }
    }
}
