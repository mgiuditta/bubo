import RemoteKit
import SwiftUI

/// The dot of a Sessione's Attività, read by VoiceOver as the Attività's name.
struct ActivityDot: View {
    let activity: SessionCard.Activity

    var body: some View {
        Circle()
            .fill(activity.color)
            .frame(width: 8, height: 8)
            .accessibilityLabel(Text(activity.title))
    }
}
