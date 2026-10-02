import DeliveryKit
import SwiftUI

/// A verification code in 3 groups of 4 digits, read by VoiceOver group by group: "4821, 0937, 5562".
struct VerificationCodeText: View {
    let code: VerificationCode

    var body: some View {
        Text(verbatim: code.description)
            .textSelection(.enabled)
            .accessibilityLabel(Text(verbatim: code.groups.joined(separator: ", ")))
    }
}
