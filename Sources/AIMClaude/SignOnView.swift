import AIMCore
import SwiftUI

struct SignOnView: View {
    let app: AppController
    let skin: SkinStore
    let onSignedOn: () -> Void
    var onHelp: () -> Void = {}
    var onSetup: () -> Void = {}
    private let name: State<String>
    private let error = State<String?>(initialValue: nil)
    /// Non-nil while the sign-on steps play; the step text.
    private let step = State<String?>(initialValue: nil)
    private let attempt = State(initialValue: 0)

    init(app: AppController, skin: SkinStore, onSignedOn: @escaping () -> Void,
         onHelp: @escaping () -> Void = {}, onSetup: @escaping () -> Void = {}) {
        self.app = app
        self.skin = skin
        self.onSignedOn = onSignedOn
        self.onHelp = onHelp
        self.onSetup = onSetup
        name = State(initialValue: app.state.screenName ?? "")
    }

    private var trimmed: String { name.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: 8) {
            banner
            EtchedRule()
            if let s = step.wrappedValue { progress(s) } else { form }
        }
        .padding(10)
        .frame(width: 230)
        .background(AIMColors.window)
    }

    private var banner: some View {
        Group {
            if let img = Skin.image("signon-banner") {
                Image(nsImage: img).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
            } else {
                ZStack {
                    LinearGradient(colors: [AIMColors.titleBlue, AIMColors.titleBlueEnd], startPoint: .top, endPoint: .bottom)
                    VStack(spacing: 6) {
                        AIMLogo(skin: skin).frame(height: 90)
                        Text("Instant Messenger").font(.custom("Verdana", size: 14).weight(.bold)).foregroundStyle(.white)
                    }
                }
            }
        }
        .frame(width: 210, height: 166)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                if Skin.image("screenname-label") != nil {
                    SkinIcon(name: "screenname-label")
                } else {
                    Text("ScreenName").font(AIMFonts.labelBold.italic()).foregroundStyle(AIMColors.titleBlue)
                }
            }
            HStack(spacing: 0) {
                TextField("<New User>", text: name.projectedValue)
                    .textFieldStyle(.plain)
                    .font(AIMFonts.label)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 2)
                    .onSubmit(signOn)
                Image(systemName: "arrowtriangle.down.fill").font(.system(size: 7))
                    .frame(width: 15, height: 17)
                    .background(AIMColors.window)
                    .modifier(Bevel.raised)
                    .padding(1)
            }
            .background(AIMColors.field)
            .modifier(Bevel.sunken)
            Text("Get a Screen Name").font(AIMFonts.label).underline().foregroundStyle(AIMFonts.link)
                .padding(.bottom, 4)

            Text("Password").font(AIMFonts.labelBold)
            Text("No need for a password yet!")
                .font(AIMFonts.label).foregroundStyle(AIMColors.shadow)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 3).padding(.vertical, 3)
                .background(AIMColors.window)
                .modifier(Bevel.sunken)
            Text("Forgot Password?").font(AIMFonts.label).underline().foregroundStyle(AIMFonts.link)

            HStack {
                AIMCheckbox("Save password")
                Spacer()
                AIMCheckbox("Auto-login")
            }
            .padding(.vertical, 6)

            if let e = error.wrappedValue {
                Text(e).font(AIMFonts.small).foregroundStyle(AIMColors.error)
            }

            HStack(alignment: .bottom) {
                SkinButton(icon: "help", title: "Help", fallback: "questionmark.circle", action: onHelp)
                SkinButton(icon: "setup", title: "Setup", fallback: "wrench.and.screwdriver", action: onSetup)
                Spacer()
                SkinButton(icon: trimmed.isEmpty ? "signon-disabled" : "signon", title: "Sign On",
                           fallback: "figure.run", action: signOn)
                    .keyboardShortcut(.defaultAction)
            }
            Text("Version: 0.1 (Claude)").font(AIMFonts.small).frame(maxWidth: .infinity)
        }
    }

    private func progress(_ text: String) -> some View {
        VStack(spacing: 10) {
            Text(trimmed).font(AIMFonts.label)
            Text(text).font(AIMFonts.label)
            Button("Cancel") {
                attempt.wrappedValue += 1
                step.wrappedValue = nil
            }
            .buttonStyle(AIMButtonStyle(isDefault: true))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    private func signOn() {
        guard !trimmed.isEmpty else {
            error.wrappedValue = "Please enter a screen name."
            return
        }
        guard step.wrappedValue == nil else { return }
        error.wrappedValue = nil
        attempt.wrappedValue += 1
        let mine = attempt.wrappedValue
        let steps = ["1. Connecting...", "2. Verifying name and password...", "3. Starting services..."]
        Task { @MainActor in
            for s in steps {
                guard attempt.wrappedValue == mine else { return }
                step.wrappedValue = s
                try? await Task.sleep(for: .milliseconds(450))
            }
            guard attempt.wrappedValue == mine else { return }
            step.wrappedValue = nil
            if app.signOn(screenName: trimmed) { onSignedOn() }
        }
    }
}
