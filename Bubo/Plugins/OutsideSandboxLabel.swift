import SwiftUI

/// The sign of a plugin with code that runs on the Mac: "gira fuori dalla sandbox".
struct OutsideSandboxLabel: View {
    var body: some View {
        Label("gira fuori dalla sandbox", systemImage: "shield.slash")
            .font(Typography.body(size: 11))
            .foregroundStyle(Palette.textSecondary)
    }
}
