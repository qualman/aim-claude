import SwiftUI

struct AIMButtonStyle: ButtonStyle {
    var isDefault = false

    func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label
            .font(AIMFonts.label)
            .foregroundStyle(AIMColors.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .frame(minWidth: 60)
            .background(AIMColors.window)
            .offset(x: configuration.isPressed ? 1 : 0, y: configuration.isPressed ? 1 : 0)
        Group {
            if configuration.isPressed { label.bevelSunken() } else { label.bevelRaised() }
        }
        .padding(isDefault ? 1 : 0)
        .overlay(isDefault ? Rectangle().stroke(Color.black, lineWidth: 1) : nil)
    }
}

/// A toolbar button: icon over a caption, flat until pressed, as on AIM's buddy list.
struct AIMToolbarButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Image(systemName: symbol).font(.system(size: 15))
                Text(title).font(AIMFonts.small)
            }
            .foregroundStyle(AIMColors.text)
            .frame(width: 52, height: 38)
        }
        .buttonStyle(AIMButtonStyle())
    }
}

/// White sunken input field.
struct AIMTextField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(AIMFonts.label)
            .padding(.horizontal, 3)
            .padding(.vertical, 2)
            .background(AIMColors.field)
            .bevelSunken()
    }
}
