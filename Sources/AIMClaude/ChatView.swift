import AIMCore
import SwiftUI

/// An AIM IM window: menu strip, transcript, formatting bar, input box, Send.
struct ChatView: View {
    let chat: ChatController
    let myName: () -> String
    private let draft = State(initialValue: "")

    init(chat: ChatController, myName: @escaping () -> String) {
        self.chat = chat
        self.myName = myName
    }

    var body: some View {
        VStack(spacing: 4) {
            menuStrip
            transcript
            status
            ForEach(chat.pendingPermissions) { r in
                PermissionPromptView(buddyName: chat.buddy?.screenName ?? "Buddy", request: r) { allow in
                    chat.resolvePermission(r.id, allow: allow)
                }
            }
            formattingBar
            input
            buttons
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 6)
        .background(AIMColors.window)
        .frame(minWidth: 380, minHeight: 360)
    }

    private var menuStrip: some View {
        HStack(spacing: 12) {
            ForEach(["File", "Edit", "Insert", "People"], id: \.self) { Text($0).font(AIMFonts.label) }
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.top, 3)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(chat.messages) { m in
                        row(m).id(m.id)
                    }
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
            .background(AIMColors.field)
            .bevelSunken()
            .onChange(of: chat.messages.count) {
                if let last = chat.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
            .onAppear {
                if let last = chat.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }

    private func row(_ m: ChatMessage) -> some View {
        let buddyName = chat.buddy?.screenName ?? "Buddy"
        let text: Text
        switch m.sender {
        case .user:
            text = Text("\(myName()): ").font(AIMFonts.messageBold).foregroundColor(AIMColors.userName)
                + Text(m.text).font(AIMFonts.message).foregroundColor(AIMColors.text)
        case .buddy:
            text = Text("\(buddyName): ").font(AIMFonts.messageBold).foregroundColor(AIMColors.buddyName)
                + Text(m.text).font(AIMFonts.message).foregroundColor(AIMColors.text)
        case .system:
            text = Text(m.text).font(AIMFonts.message.italic()).foregroundColor(AIMColors.system)
        case .error:
            text = Text(m.text).font(AIMFonts.message.italic()).foregroundColor(AIMColors.error)
        }
        return text.fixedSize(horizontal: false, vertical: true)
    }

    private var status: some View {
        Text(chat.statusLine ?? " ")
            .font(AIMFonts.small)
            .foregroundStyle(AIMColors.shadow)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 2)
    }

    private var formattingBar: some View {
        HStack(spacing: 2) {
            ForEach(["A", "a", "B", "I", "U"], id: \.self) { s in
                Text(s).font(.custom("Times New Roman", size: 13).weight(s == "B" ? .bold : .regular))
                    .italic(s == "I").underline(s == "U")
                    .frame(width: 20, height: 18)
                    .background(AIMColors.window).bevelRaised()
            }
            Spacer()
        }
    }

    private var input: some View {
        TextEditor(text: draft.projectedValue)
            .font(AIMFonts.message)
            .scrollContentBackground(.hidden)
            .background(AIMColors.field)
            .frame(height: 64)
            .bevelSunken()
            .onKeyPress(.return, phases: .down) { press in
                if press.modifiers.contains(.shift) { return .ignored }
                sendDraft()
                return .handled
            }
    }

    private var buttons: some View {
        HStack(spacing: 6) {
            Button("Warn") {}.buttonStyle(AIMButtonStyle()).disabled(true).opacity(0.6)
            Button("Block") {}.buttonStyle(AIMButtonStyle()).disabled(true).opacity(0.6)
            Spacer()
            Button("Send", action: sendDraft).buttonStyle(AIMButtonStyle(isDefault: true))
        }
    }

    private func sendDraft() {
        let text = draft.wrappedValue
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        draft.wrappedValue = ""
        chat.send(text)
    }
}
