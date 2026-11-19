import AIMCore
import SwiftUI

/// Shows where `claude` was found and lets the user point AIM at a different one.
struct PreferencesView: View {
    let app: AppController
    let onSave: () -> Void
    private let override: State<String>

    init(app: AppController, onSave: @escaping () -> Void) {
        self.app = app
        self.onSave = onSave
        override = State(initialValue: app.state.claudePathOverride ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Claude").font(AIMFonts.labelBold)
            VStack(alignment: .leading, spacing: 6) {
                Text("Using:").font(AIMFonts.label)
                Text(app.claudePath?.path ?? (app.claudeMissing ? "Not found" : "Looking…"))
                    .font(AIMFonts.message)
                    .foregroundStyle(app.claudeMissing ? AIMColors.error : AIMColors.text)
                    .textSelection(.enabled)
                Text("Custom path (leave blank to find it automatically):").font(AIMFonts.label)
                AIMTextField(placeholder: "/path/to/claude", text: override.projectedValue)
            }
            .padding(8)
            .etched()
            Text("Skin folder: \(AppPaths.skin.path)").font(AIMFonts.small).foregroundStyle(AIMColors.shadow)
                .textSelection(.enabled)
            HStack {
                Spacer()
                Button("Save") {
                    app.setClaudePathOverride(override.wrappedValue)
                    onSave()
                }
                .buttonStyle(AIMButtonStyle(isDefault: true))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .frame(width: 400)
        .background(AIMColors.window)
    }
}
