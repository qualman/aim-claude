import AIMCore
import AppKit
import SwiftUI

/// What the formatting bar's buttons do.
enum FormatCommand: CaseIterable {
    case color, background, smaller, normal, bigger, bold, italic, underline, link, image, smiley
}

/// Drives one rich text view: formatting commands, loading and reading its contents as RTFD.
@MainActor
final class RichTextController: NSObject {
    fileprivate(set) var textView: NSTextView?
    /// Asks the user for a link URL; the WindowManager shows an AIM dialog. nil = cancelled.
    var askLink: (_ done: @escaping (String?) -> Void) -> Void = { $0(nil) }
    var skin: SkinStore?
    private var pending: Data?
    private var colorRange: NSRange?
    private var colorKey: NSAttributedString.Key = .foregroundColor

    /// AIM's seven font sizes; "normal" is the third.
    static let sizes: [CGFloat] = [10, 12, 14, 16, 20, 28, 40]
    static let normalSize = sizes[2]
    static var baseFont: NSFont { NSFont(name: "Times New Roman", size: normalSize) ?? .systemFont(ofSize: normalSize) }

    /// Replaces the contents (RTFD, or RTF). Before the view exists, it's applied on creation.
    func load(_ rich: Data) {
        guard let tv = textView else { pending = rich; return }
        let s = Self.attributed(rich) ?? NSAttributedString()
        tv.textStorage?.setAttributedString(s)
        tv.typingAttributes = [.font: Self.baseFont, .foregroundColor: NSColor.black]
    }

    /// RTFD keeps images and smileys; `text` is the plain version with attachments dropped.
    var contents: (rich: Data, text: String) {
        guard let s = textView?.attributedString() else { return (Data(), "") }
        let rich = s.rtfd(from: NSRange(location: 0, length: s.length), documentAttributes: [:]) ?? Data()
        let text = s.string.replacingOccurrences(of: "\u{FFFC}", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        return (rich, text)
    }

    static func attributed(_ rich: Data) -> NSAttributedString? {
        guard !rich.isEmpty else { return nil }
        return NSAttributedString(rtfd: rich, documentAttributes: nil) ?? NSAttributedString(rtf: rich, documentAttributes: nil)
    }

    func attach(_ tv: NSTextView) {
        textView = tv
        if let p = pending { pending = nil; load(p) }
    }

    func perform(_ cmd: FormatCommand) {
        guard let tv = textView else { return }
        tv.window?.makeFirstResponder(tv)
        switch cmd {
        case .bold: toggleTrait(.boldFontMask)
        case .italic: toggleTrait(.italicFontMask)
        case .underline: toggleUnderline()
        case .smaller: resize { s in Self.sizes.last { $0 < s } ?? Self.sizes[0] }
        case .bigger: resize { s in Self.sizes.first { $0 > s } ?? Self.sizes[Self.sizes.count - 1] }
        case .normal: resize { _ in Self.normalSize }
        case .color: pickColor(.foregroundColor)
        case .background: pickColor(.backgroundColor)
        case .link: addLink()
        case .image: insertImage()
        case .smiley: showSmileys()
        }
    }

    // MARK: Styling

    /// Changes the selection, or what's typed next when nothing is selected.
    private func change(_ key: NSAttributedString.Key, _ transform: (Any?) -> Any?) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let r = tv.selectedRange()
        if r.length == 0 {
            var a = tv.typingAttributes
            a[key] = transform(a[key])
            tv.typingAttributes = a
            return
        }
        guard tv.shouldChangeText(in: r, replacementString: nil) else { return }
        storage.beginEditing()
        storage.enumerateAttribute(key, in: r) { value, sub, _ in
            if let v = transform(value) { storage.addAttribute(key, value: v, range: sub) } else { storage.removeAttribute(key, range: sub) }
        }
        storage.endEditing()
        tv.didChangeText()
    }

    /// The font at the start of the selection (or typing position) decides on or off for the whole range.
    private var currentFont: NSFont {
        guard let tv = textView else { return Self.baseFont }
        let r = tv.selectedRange()
        if r.length > 0, let f = tv.textStorage?.attribute(.font, at: r.location, effectiveRange: nil) as? NSFont { return f }
        return tv.typingAttributes[.font] as? NSFont ?? Self.baseFont
    }

    private func toggleTrait(_ trait: NSFontTraitMask) {
        let fm = NSFontManager.shared
        let on = !fm.traits(of: currentFont).contains(trait)
        change(.font) { v in
            let f = v as? NSFont ?? Self.baseFont
            return on ? fm.convert(f, toHaveTrait: trait) : fm.convert(f, toNotHaveTrait: trait)
        }
    }

    private func toggleUnderline() {
        guard let tv = textView else { return }
        let r = tv.selectedRange()
        let now = r.length > 0 ? tv.textStorage?.attribute(.underlineStyle, at: r.location, effectiveRange: nil) : tv.typingAttributes[.underlineStyle]
        let on = (now as? Int ?? 0) == 0
        change(.underlineStyle) { _ in on ? NSUnderlineStyle.single.rawValue : nil }
    }

    private func resize(_ next: @escaping (CGFloat) -> CGFloat) {
        change(.font) { v in
            let f = v as? NSFont ?? Self.baseFont
            return NSFontManager.shared.convert(f, toSize: next(f.pointSize))
        }
    }

    private func pickColor(_ key: NSAttributedString.Key) {
        colorKey = key
        colorRange = textView?.selectedRange()
        let panel = NSColorPanel.shared
        panel.setTarget(self)
        panel.setAction(#selector(colorPicked(_:)))
        panel.orderFront(nil)
    }

    @objc private func colorPicked(_ panel: NSColorPanel) {
        guard let tv = textView, let r = colorRange else { return }
        tv.setSelectedRange(r)
        change(colorKey) { _ in panel.color }
    }

    private func addLink() {
        guard let tv = textView else { return }
        let r = tv.selectedRange()
        askLink { [weak self] raw in
            guard let self, let raw, let tv = self.textView else { return }
            let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !s.isEmpty, let url = URL(string: s.contains("://") ? s : "https://\(s)") else { return }
            if r.length == 0 {
                // Nothing selected: insert the address itself as the link text.
                var a = tv.typingAttributes
                a[.link] = url
                tv.insertText(NSAttributedString(string: s, attributes: a), replacementRange: r)
            } else {
                tv.setSelectedRange(r)
                self.change(.link) { _ in url }
            }
        }
    }

    private func insertImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let url = panel.url, let img = NSImage(contentsOf: url) else { return }
        // Fit wide pictures to the editor, as AIM did.
        let maxW: CGFloat = 220
        if img.size.width > maxW { img.size = NSSize(width: maxW, height: img.size.height * maxW / img.size.width) }
        insert(img, name: url.lastPathComponent)
    }

    private func showSmileys() {
        guard let tv = textView else { return }
        let menu = NSMenu()
        let faces = skin?.smileys() ?? []
        if faces.isEmpty {
            for e in ["🙂", "😉", "😛", "😮", "😎", "😢", "😠", "😂"] {
                let it = menu.addItem(withTitle: e, action: #selector(insertEmoji(_:)), keyEquivalent: "")
                it.target = self
            }
        } else {
            for (name, url) in faces {
                let it = menu.addItem(withTitle: name.replacingOccurrences(of: "-", with: " "), action: #selector(insertFace(_:)), keyEquivalent: "")
                it.image = NSImage(contentsOf: url)
                it.representedObject = url
                it.target = self
            }
        }
        menu.popUp(positioning: nil, at: NSPoint(x: tv.bounds.maxX - 30, y: 0), in: tv)
    }

    @objc private func insertEmoji(_ item: NSMenuItem) { textView?.insertText(item.title, replacementRange: textView?.selectedRange() ?? NSRange()) }

    @objc private func insertFace(_ item: NSMenuItem) {
        guard let url = item.representedObject as? URL, let img = NSImage(contentsOf: url) else { return }
        if let rep = img.representations.first { img.size = NSSize(width: rep.pixelsWide, height: rep.pixelsHigh) }
        insert(img, name: url.lastPathComponent)
    }

    private func insert(_ img: NSImage, name: String) {
        guard let tv = textView, let tiff = img.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        let wrapper = FileWrapper(regularFileWithContents: png)
        wrapper.preferredFilename = (name as NSString).deletingPathExtension + ".png"
        let att = NSTextAttachment(fileWrapper: wrapper)
        att.image = img
        att.bounds = CGRect(x: 0, y: -4, width: img.size.width, height: img.size.height)
        tv.insertText(NSAttributedString(attachment: att), replacementRange: tv.selectedRange())
    }
}

/// A white, sunken rich text box. Read-only when `editable` is false.
struct RichTextView: NSViewRepresentable {
    let controller: RichTextController
    var editable = true

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = true
        scroll.backgroundColor = .white
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let tv = scroll.documentView as! NSTextView
        tv.isRichText = true
        tv.importsGraphics = true
        tv.allowsUndo = true
        tv.isEditable = editable
        tv.isSelectable = true
        tv.drawsBackground = true
        tv.backgroundColor = .white
        tv.textColor = .black
        tv.insertionPointColor = .black
        tv.textContainerInset = NSSize(width: 4, height: 4)
        tv.font = RichTextController.baseFont
        tv.typingAttributes = [.font: RichTextController.baseFont, .foregroundColor: NSColor.black]
        tv.linkTextAttributes = [.foregroundColor: NSColor.blue, .underlineStyle: NSUnderlineStyle.single.rawValue,
                                 .cursor: NSCursor.pointingHand]
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        controller.attach(tv)
        return scroll
    }

    func updateNSView(_ view: NSScrollView, context: Context) {}
}

/// AIM's font / link / image / smiley strip. With `perform`, each button works on the text box;
/// without it, it's decorative (the IM window, since Claude reads plain text).
struct FormattingBar: View {
    var perform: ((FormatCommand) -> Void)?

    private static let groups: [[(FormatCommand, String, String, String)]] = [
        [(.color, "fmt-color", "A", "Text Color"), (.background, "fmt-background", "A", "Background Color")],
        [(.smaller, "fmt-smaller", "a", "Smaller Text"), (.normal, "fmt-normal", "A", "Normal Text"), (.bigger, "fmt-bigger", "A", "Bigger Text")],
        [(.bold, "fmt-bold", "B", "Bold"), (.italic, "fmt-italic", "I", "Italic"), (.underline, "fmt-underline", "U", "Underline")],
        [(.link, "fmt-link", "link", "Insert Link"), (.image, "fmt-image", "▣", "Insert Picture"), (.smiley, "fmt-smiley", "☺", "Insert Smiley")],
    ]

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            ForEach(Self.groups.indices, id: \.self) { g in
                if g > 0 { Rectangle().fill(AIMColors.shadow).frame(width: 1, height: 16).padding(.horizontal, 6) }
                HStack(spacing: perform == nil ? 10 : 4) {
                    ForEach(Self.groups[g], id: \.1) { cmd, icon, text, help in
                        let face = Group {
                            if Skin.image(icon) != nil { SkinIcon(name: icon) } else { Text(text).font(AIMFonts.labelBold) }
                        }
                        .frame(height: 14)
                        if let perform {
                            Button { perform(cmd) } label: { face }
                                .buttonStyle(FlatIconButtonStyle())
                                .help(help)
                        } else {
                            face
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, perform == nil ? 5 : 1)
        .modifier(Bevel.etched)
        .help(perform == nil ? "Formatting isn't sent to Claude" : "")
    }
}
