import AIMCore
import AppKit
import CoreText
import SwiftUI

/// The user's skin folder: icons, fonts. Everything has a fallback when a file is missing.
@MainActor
enum Skin {
    static let store = SkinStore(directory: AppPaths.skin)
    private static var cache: [String: NSImage] = [:]

    static func image(_ name: String) -> NSImage? {
        if let i = cache[name] { return i }
        guard let url = store.icon(name), let img = NSImage(contentsOf: url) else { return nil }
        // Points = pixels, as the art was drawn for 96 dpi.
        if let rep = img.representations.first { img.size = NSSize(width: rep.pixelsWide, height: rep.pixelsHigh) }
        cache[name] = img
        return img
    }

    /// Registers skin fonts (MS Sans Serif) for this process. Call before any window is built.
    static func registerFonts() {
        for url in store.fonts() {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        AIMFonts.hasMSSans = NSFont(name: "MS-Sans-Serif", size: 11) != nil
    }
}

/// A skin icon at its native pixel size, or an SF Symbol stand-in.
struct SkinIcon: View {
    let name: String
    var fallback: String = "questionmark.square"
    var fallbackSize: CGFloat = 16

    var body: some View {
        if let img = Skin.image(name) {
            Image(nsImage: img).interpolation(.none)
        } else {
            Image(systemName: fallback).font(.system(size: fallbackSize)).foregroundStyle(AIMColors.text)
        }
    }
}

/// AIM's icon buttons: flat, with a sunken bevel only while pressed.
struct FlatIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(3)
            .offset(x: configuration.isPressed ? 1 : 0, y: configuration.isPressed ? 1 : 0)
            .modifier(configuration.isPressed ? Bevel.sunken : Bevel.none)
            .contentShape(Rectangle())
    }
}

/// An icon whose art includes its caption (Warn, Send, ...), drawn as AIM did: no box, and the
/// "<icon>-hover" art while the pointer is over it. Falls back to symbol + text with a pressed bevel.
struct SkinButton: View {
    let icon: String
    let title: String
    let fallback: String
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    private let hovering = State(initialValue: false)
    /// Render mode only (AIM_RENDER_HOVER=1): draw every button as hovered.
    @MainActor static var previewHover = false

    init(icon: String, title: String, fallback: String, action: @escaping () -> Void) {
        self.icon = icon
        self.title = title
        self.fallback = fallback
        self.action = action
    }

    var body: some View {
        if let art = Skin.image(icon) {
            // Disabled: the "<icon>-disabled" art if there is one, otherwise the normal art faded.
            let disabledArt = isEnabled ? nil : Skin.image(icon + "-disabled")
            let normal = disabledArt ?? art
            let hover = Skin.image(icon + "-hover")
            let showHover = hover != nil && (hovering.wrappedValue || Self.previewHover) && isEnabled
            Button(action: action) {
                // Both images stay in the view so it never changes identity mid-click, and the
                // button keeps the larger of the two sizes so nothing shifts on hover.
                ZStack(alignment: .topLeading) {
                    Image(nsImage: normal).interpolation(.none)
                        .opacity(showHover ? 0 : (isEnabled || disabledArt != nil ? 1 : 0.4))
                    if let hover { Image(nsImage: hover).interpolation(.none).opacity(showHover ? 1 : 0) }
                }
            }
            .buttonStyle(SkinArtButtonStyle())
            .onHover { hovering.wrappedValue = $0 }
            .help(title)
        } else {
            Button(action: action) {
                VStack(spacing: 1) {
                    Image(systemName: fallback).font(.system(size: 16))
                    Text(title).font(AIMFonts.small)
                }
                .foregroundStyle(AIMColors.text)
            }
            .buttonStyle(FlatIconButtonStyle())
            .help(title)
        }
    }
}

/// Skin art buttons have no pressed look of their own; the hit area reaches 4 pt past the art, as on AIM Rewind.
struct SkinArtButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(4)
            .contentShape(Rectangle())
            .padding(-4)
    }
}

/// The 2px etched groove AIM uses between sections.
struct EtchedRule: View {
    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(AIMColors.shadow).frame(height: 1)
            Rectangle().fill(AIMColors.highlight).frame(height: 1)
        }
    }
}

/// In-window menu strip (MyAIM / People / Help, File / Edit / View / People).
struct MenuStrip<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 14) {
            content
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct StripMenu<Items: View>: View {
    let title: String
    @ViewBuilder let items: Items

    var body: some View {
        Menu {
            items
        } label: {
            Text(title).font(AIMFonts.label).foregroundStyle(AIMColors.text)
        }
        .fixedSize()
    }
}

/// White box with a check, drawn like Win98 rather than a macOS checkbox.
struct AIMCheckbox: View {
    let title: String
    private let local = State(initialValue: false)
    private let bound: Binding<Bool>?

    /// Without a binding the box keeps its own (unused) state, as on the Sign On window.
    init(_ title: String, isOn: Binding<Bool>? = nil) {
        self.title = title
        self.bound = isOn
    }

    private var on: Binding<Bool> { bound ?? local.projectedValue }

    var body: some View {
        Button { on.wrappedValue.toggle() } label: {
            HStack(spacing: 5) {
                ZStack {
                    Rectangle().fill(AIMColors.field).frame(width: 9, height: 9)
                    if on.wrappedValue { Image(systemName: "checkmark").font(.system(size: 8, weight: .heavy)) }
                }
                .modifier(Bevel.sunken)
                Text(title).font(AIMFonts.label)
            }
            .foregroundStyle(AIMColors.text)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
