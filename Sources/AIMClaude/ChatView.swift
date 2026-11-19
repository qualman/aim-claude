import AIMCore
import SwiftUI

struct ChatActions {
    var addBuddy: () -> Void = {}
    var getInfo: () -> Void = {}
    var close: () -> Void = {}
}

/// An AIM IM window: menu strip, buddy icon, transcript, formatting bar, input, button bar.
struct ChatView: View {
    let chat: ChatController
    let myName: () -> String
    let actions: ChatActions
    private let draft = State(initialValue: "")

    init(chat: ChatController, myName: @escaping () -> String, actions: ChatActions = ChatActions()) {
        self.chat = chat
        self.myName = myName
        self.actions = actions
    }

    var body: some View {
        VStack(spacing: 0) {
            MenuStrip {
                StripMenu(title: "File") { Button("Close", action: actions.close) }
                StripMenu(title: "Edit") {
                    Button("Clear Draft") { draft.wrappedValue = "" }
                }
                StripMenu(title: "View") { Button("Get Info", action: actions.getInfo) }
                StripMenu(title: "People") {
                    Button("Add Buddy…", action: actions.addBuddy)
                    Button("Get Info", action: actions.getInfo)
                }
            }
            EtchedRule()
            HStack(alignment: .top, spacing: 8) {
                SkinIcon(name: "buddy-robot", fallback: "person.crop.square", fallbackSize: 30)
                    .frame(width: 56)
                    .padding(.top, 6)
                VStack(spacing: 6) {
                    transcript
                    status
                    ForEach(chat.pendingPermissions) { r in
                        PermissionPromptView(buddyName: chat.buddy?.screenName ?? "Buddy", request: r) { allow in
                            chat.resolvePermission(r.id, allow: allow)
                        }
                    }
                    formattingBar
                    input
                    buttonBar
                }
            }
            .padding(8)
        }
        .background(AIMColors.window)
        .frame(minWidth: 430, minHeight: 360)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(chat.messages) { m in row(m).id(m.id) }
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
            .background(AIMColors.field)
            .modifier(Bevel.sunken)
            .onChange(of: chat.messages.count) {
                if let last = chat.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
            .onAppear {
                if let last = chat.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
        .frame(minHeight: 120)
    }

    private func row(_ m: ChatMessage) -> some View {
        let text: Text
        switch m.sender {
        case .user:
            text = Text("\(myName()): ").font(AIMFonts.messageBold).foregroundColor(AIMColors.userName)
                + Text(m.text).font(AIMFonts.message).foregroundColor(AIMColors.text)
        case .buddy:
            text = Text("\(chat.buddy?.screenName ?? "Buddy"): ").font(AIMFonts.messageBold).foregroundColor(AIMColors.buddyName)
                + Text(m.text).font(AIMFonts.message).foregroundColor(AIMColors.text)
        case .system:
            text = Text(m.text).font(AIMFonts.message.italic()).foregroundColor(AIMColors.system)
        case .error:
            text = Text(m.text).font(AIMFonts.message.italic()).foregroundColor(AIMColors.error)
        }
        return text.fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var status: some View {
        if let s = chat.statusLine {
            Text(s).font(AIMFonts.small).foregroundStyle(AIMColors.shadow)
                .lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// AIM's font/link/image/smiley strip. Decorative: replies are plain text.
    private var formattingBar: some View {
        let groups: [[(String, String)]] = [
            [("fmt-color", "A"), ("fmt-background", "A")],
            [("fmt-smaller", "a"), ("fmt-normal", "A"), ("fmt-bigger", "A")],
            [("fmt-bold", "B"), ("fmt-italic", "I"), ("fmt-underline", "U")],
            [("fmt-link", "link"), ("fmt-image", "▣"), ("fmt-smiley", "☺")],
        ]
        return HStack(spacing: 0) {
            Spacer(minLength: 0)
            ForEach(groups.indices, id: \.self) { g in
                if g > 0 { Rectangle().fill(AIMColors.shadow).frame(width: 1, height: 16).padding(.horizontal, 6) }
                HStack(spacing: 10) {
                    ForEach(groups[g], id: \.0) { icon, text in
                        Group {
                            if Skin.image(icon) != nil { SkinIcon(name: icon) } else { Text(text).font(AIMFonts.labelBold) }
                        }
                        .frame(height: 14)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        .modifier(Bevel.etched)
        .help("Formatting isn't sent to Claude")
    }

    private var input: some View {
        TextEditor(text: draft.projectedValue)
            .font(AIMFonts.message)
            .scrollContentBackground(.hidden)
            .background(AIMColors.field)
            .frame(height: 64)
            .modifier(Bevel.sunken)
            .onKeyPress(.return, phases: .down) { press in
                if press.modifiers.contains(.shift) { return .ignored }
                sendDraft()
                return .handled
            }
    }

    private var buttonBar: some View {
        HStack(spacing: 6) {
            HStack(spacing: 8) {
                SkinButton(icon: "warn", title: "Warn", fallback: "bolt", action: {}).disabled(true)
                SkinButton(icon: "block", title: "Block", fallback: "nosign", action: {}).disabled(true)
            }
            .padding(4).modifier(Bevel.etched)
            HStack(spacing: 24) {
                SkinButton(icon: "add-buddy", title: "Add Buddy", fallback: "person.badge.plus", action: actions.addBuddy)
                SkinButton(icon: "get-info", title: "Get Info", fallback: "info.circle", action: actions.getInfo)
            }
            .frame(maxWidth: .infinity)
            .padding(4).modifier(Bevel.etched)
            VStack(spacing: 2) {
                SkinButton(icon: "send", title: "Send", fallback: "paperplane", action: sendDraft)
                SendMeter(busy: chat.inFlight > 0)
            }
            .padding(4).modifier(Bevel.etched)
        }
    }

    private func sendDraft() {
        let text = draft.wrappedValue
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        draft.wrappedValue = ""
        chat.send(text)
    }
}

/// The green-to-red bar under Send. Lit while the buddy is working.
struct SendMeter: View {
    let busy: Bool

    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<14, id: \.self) { i in
                Rectangle()
                    .fill(color(i).opacity(busy || i < 2 ? 1 : 0.35))
                    .frame(width: 3, height: 6)
            }
        }
        .padding(1)
        .background(Color.black)
    }

    private func color(_ i: Int) -> Color {
        i < 3 ? .red : (i < 8 ? .yellow : .green)
    }
}
