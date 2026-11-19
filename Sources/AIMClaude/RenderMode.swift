import AppKit
import SwiftUI

/// Dev tool: `AIMClaude --render <dir>` writes PNGs of each screen and exits.
/// Lets the look be checked without screen-recording permission.
@MainActor
enum RenderMode {
    static var screens: [(String, AnyView)] = [("gallery", AnyView(LookGallery()))]

    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--render"), i + 1 < args.count else { return }
        let dir = URL(fileURLWithPath: args[i + 1])
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, view) in screens {
            let r = ImageRenderer(content: view.environment(\.colorScheme, .light))
            r.scale = 2
            if let img = r.nsImage, let tiff = img.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: dir.appendingPathComponent("\(name).png"))
            }
        }
        exit(0)
    }
}

struct LookGallery: View {
    private let text = State(initialValue: "SkaterBoi99")

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Raised").font(AIMFonts.label).frame(width: 90, height: 40).background(AIMColors.window).bevelRaised()
                Text("Sunken").font(AIMFonts.label).frame(width: 90, height: 40).background(AIMColors.field).bevelSunken()
            }
            HStack(spacing: 8) {
                Button("Sign On") {}.buttonStyle(AIMButtonStyle(isDefault: true))
                Button("Cancel") {}.buttonStyle(AIMButtonStyle())
                AIMToolbarButton(title: "IM", symbol: "bubble.left") {}
            }
            AIMTextField(placeholder: "Screen Name", text: text.projectedValue).frame(width: 200)
            VStack(alignment: .leading, spacing: 2) {
                (Text("SkaterBoi99: ").font(AIMFonts.messageBold).foregroundColor(AIMColors.userName)
                 + Text("hey whats up").font(AIMFonts.message))
                (Text("xX_Claude_Xx: ").font(AIMFonts.messageBold).foregroundColor(AIMColors.buddyName)
                 + Text("func hello() { print(\"hi\") }").font(AIMFonts.message))
            }
            .padding(6)
            .frame(width: 320, alignment: .leading)
            .background(AIMColors.field)
            .bevelSunken()
        }
        .padding(12)
        .background(AIMColors.window)
    }
}
