import AIMCore
import SwiftUI

struct SignOnView: View {
    let app: AppController
    let skin: SkinStore
    let onSignedOn: () -> Void
    private let name: State<String>
    private let error = State<String?>(initialValue: nil)

    init(app: AppController, skin: SkinStore, onSignedOn: @escaping () -> Void) {
        self.app = app
        self.skin = skin
        self.onSignedOn = onSignedOn
        name = State(initialValue: app.state.screenName ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                LinearGradient(colors: [AIMColors.titleBlue, AIMColors.titleBlueEnd], startPoint: .top, endPoint: .bottom)
                VStack(spacing: 6) {
                    AIMLogo(skin: skin).frame(height: 96)
                    Text("Instant Messenger").font(.custom("Verdana", size: 15).weight(.bold)).foregroundStyle(.white)
                }
                .padding(.vertical, 14)
            }
            .frame(height: 160)
            .bevelSunken()
            .padding(8)

            VStack(alignment: .leading, spacing: 4) {
                Text("ScreenName").font(AIMFonts.labelBold)
                AIMTextField(placeholder: "", text: name.projectedValue)
                Text("Your buddies will see this name.").font(AIMFonts.small).foregroundStyle(AIMColors.shadow)
                if let e = error.wrappedValue {
                    Text(e).font(AIMFonts.small).foregroundStyle(AIMColors.error)
                }
            }
            .padding(10)
            .etched()
            .padding(.horizontal, 8)

            HStack {
                Spacer()
                Button("Sign On") {
                    if app.signOn(screenName: name.wrappedValue) {
                        onSignedOn()
                    } else {
                        error.wrappedValue = "Please enter a screen name."
                    }
                }
                .buttonStyle(AIMButtonStyle(isDefault: true))
                .keyboardShortcut(.defaultAction)
            }
            .padding(10)
        }
        .frame(width: 250)
        .background(AIMColors.window)
    }
}
