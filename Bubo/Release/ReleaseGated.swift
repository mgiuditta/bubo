import SwiftUI

/// The entrance of a `ReleaseArea`: its content when the area is available, «Arriverà presto» otherwise.
struct ReleaseGated<Content: View>: View {
    private let area: ReleaseArea
    private let content: Content
    @AppStorage(ReleaseArea.hidesUnreleasedKey) private var hidesUnreleased = false

    /// Creates the entrance of `area`, showing `content` while the area is available.
    init(_ area: ReleaseArea, @ViewBuilder content: () -> Content) {
        self.area = area
        self.content = content()
    }

    var body: some View {
        if area.isAvailable(hidesUnreleased: hidesUnreleased) {
            content
        } else {
            ComingSoonView(area: area)
        }
    }
}
