import SwiftUI

/// A small AIM-style message box: icon, text, optional text field, buttons.
struct AIMDialog: View {
    let message: String
    var symbol = "exclamationmark.triangle.fill"
    var field: Binding<String>? = nil
    var primary = "OK"
    var secondary: String? = nil
    let onPrimary: () -> Void
    var onSecondary: () -> Void = {}

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol).font(.system(size: 26)).foregroundStyle(.yellow, .black)
                Text(message).font(AIMFonts.label).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            if let field {
                AIMTextField(placeholder: "", text: field)
            }
            HStack(spacing: 8) {
                Spacer()
                Button(primary, action: onPrimary)
                    .buttonStyle(AIMButtonStyle(isDefault: true))
                    .keyboardShortcut(.defaultAction)
                if let secondary {
                    Button(secondary, action: onSecondary)
                        .buttonStyle(AIMButtonStyle())
                        .keyboardShortcut(.cancelAction)
                }
                Spacer()
            }
        }
        .padding(14)
        .frame(width: 320)
        .background(AIMColors.window)
    }
}
