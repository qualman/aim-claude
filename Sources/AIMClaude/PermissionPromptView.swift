import AIMCore
import SwiftUI

/// "xX_Claude_Xx wants permission" panel with Allow / Deny, shown above the input box.
struct PermissionPromptView: View {
    let buddyName: String
    let request: PermissionRequest
    let onAnswer: (Bool) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 18)).foregroundStyle(.yellow, .black)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(buddyName) wants permission:").font(AIMFonts.labelBold)
                Text(request.inputSummary).font(AIMFonts.message).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Button("Allow") { onAnswer(true) }.buttonStyle(AIMButtonStyle(isDefault: true))
            Button("Deny") { onAnswer(false) }.buttonStyle(AIMButtonStyle())
        }
        .padding(6)
        .background(Color(red: 1, green: 1, blue: 0.882)) // tooltip yellow #FFFFE1
        .bevelRaised()
    }
}
