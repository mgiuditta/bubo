import Foundation

/// What the notification of a Richiesta di permesso shows, and whether it may offer Solo ora.
///
/// Solo ora is offered only on levels 1–3, never outside the Sandbox, and only when the whole command, file or address fits the notification
/// as it is: anything longer, on more lines, with invisible characters, or with no such subject is approved in the HUD.
/// No is always offered.
nonisolated struct PermissionNotice: Equatable {
    /// The longest subject shown whole: one short line, which a banner does not cut.
    static let maxLength = 80

    /// The Livello di rischio.
    let subtitle: String
    /// The subject, whole or cut; when Solo ora is not offered, first a line that says to open Bubo.
    let body: String
    /// Whether the notification may approve the call with Solo ora.
    let offersAllowOnce: Bool

    /// The notice of `pending`.
    init(_ pending: RequestCenter.Pending) {
        let request = pending.request
        let subject = request.command ?? request.path ?? request.url
        // Every invisible or control character written out, as in the HUD: a notification never hides one.
        let shown = RepoActivations.escaped(subject ?? request.title ?? request.tool)
        let isCut = shown.count > Self.maxLength
        let isWhole = !isCut && subject.map { shown == $0.replacing("\\", with: "\\\\") } == true
        let text = if isWhole, let subject { subject } else if isCut { String(shown.prefix(Self.maxLength)) + "…" } else { shown }
        offersAllowOnce = isWhole && !pending.needsHold && !request.isOutsideSandbox
        subtitle = String(localized: "Livello \(pending.risk.level.rawValue) · \(String(localized: pending.risk.level.title))")
        body = if offersAllowOnce {
            text
        } else if isCut {
            String(localized: "Testo troncato: apri Bubo per leggerlo tutto.") + "\n" + text
        } else {
            String(localized: "Per approvarla, apri Bubo.") + "\n" + text
        }
    }
}
