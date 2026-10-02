import CoreGraphics
import Foundation

/// A width the Anteprima shows the page at, with the user agent of that kind of device (spec 15). Touch and pixel
/// density are not simulated: for those there are the Simulator and the Web Inspector.
nonisolated enum PreviewWidth: String, CaseIterable, Identifiable, Sendable {
    case phone, tablet, desktop

    var id: Self { self }

    /// The name in the panel.
    var title: LocalizedStringResource {
        switch self {
        case .phone: "Telefono"
        case .tablet: "Tablet"
        case .desktop: "Desktop"
        }
    }

    var systemImage: String {
        switch self {
        case .phone: "iphone"
        case .tablet: "ipad"
        case .desktop: "desktopcomputer"
        }
    }

    /// The page's width in points; `nil` for the whole panel.
    var points: CGFloat? {
        switch self {
        case .phone: 390
        case .tablet: 820
        case .desktop: nil
        }
    }

    /// What the page reads in `navigator.userAgent`; `nil` for WebKit's own, a Mac's.
    var userAgent: String? {
        switch self {
        case .phone:
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) "
                + "Version/26.0 Mobile/15E148 Safari/604.1"
        case .tablet:
            "Mozilla/5.0 (iPad; CPU OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) "
                + "Version/26.0 Mobile/15E148 Safari/604.1"
        case .desktop: nil
        }
    }
}
