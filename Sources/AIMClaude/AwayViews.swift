import AIMCore
import AppKit
import SwiftUI

/// "Edit Away Message": a label (with saved messages in its dropdown), a rich text box, and
/// Save for later use. I'm Away goes away; nothing is ever sent to the buddies.
struct AwayEditorView: View {
    let app: AppController
    let editor: RichTextController
    let onAway: (_ label: String, _ save: Bool) -> Void
    let onCancel: () -> Void
    private let label: State<String>
    private let save = State(initialValue: false)

    init(app: AppController, editor: RichTextController, label: String = "",
         onAway: @escaping (String, Bool) -> Void, onCancel: @escaping () -> Void) {
        self.app = app
        self.editor = editor
        self.onAway = onAway
        self.onCancel = onCancel
        self.label = State(initialValue: label)
    }

    private var saved: AwayMessage? {
        let l = label.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return app.state.savedAwayMessages.first { $0.label == l }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Enter label:").font(AIMFonts.label)
                Spacer()
                labelCombo.frame(width: 190)
            }
            Text("Enter new Away message:").font(AIMFonts.label)
            VStack(spacing: 0) {
                FormattingBar(perform: editor.perform)
                RichTextView(controller: editor)
                    .frame(height: 96)
                    .modifier(Bevel.sunken)
            }
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Special Characters:")
                    Text("%d  =  Current Date")
                    Text("%t  =  Current Time")
                }
                .font(AIMFonts.label)
                Spacer()
                AIMCheckbox("Save for later use", isOn: save.projectedValue)
            }
            HStack(spacing: 10) {
                if let s = saved {
                    Button("Delete") { app.deleteSavedAwayMessage(s.id) }
                        .buttonStyle(AIMButtonStyle())
                        .help("Forget the saved message \"\(s.label)\"")
                }
                Spacer()
                Button("I'm Away") { onAway(label.wrappedValue, save.wrappedValue) }
                    .buttonStyle(AIMButtonStyle(isDefault: true))
                Button("Cancel", action: onCancel)
                    .buttonStyle(AIMButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Spacer()
            }
        }
        .padding(14)
        .frame(width: 380)
        .background(AIMColors.window)
    }

    /// A Win98 combo box: type a new label, or pick a saved message to load it.
    private var labelCombo: some View {
        HStack(spacing: 0) {
            TextField("", text: label.projectedValue)
                .textFieldStyle(.plain)
                .font(AIMFonts.label)
                .padding(.horizontal, 3)
            Menu {
                if app.state.savedAwayMessages.isEmpty {
                    Text("No saved messages")
                }
                ForEach(app.state.savedAwayMessages) { m in
                    Button(m.label) {
                        label.wrappedValue = m.label
                        editor.load(m.rich)
                    }
                }
            } label: {
                Text("▼").font(.system(size: 7)).foregroundStyle(AIMColors.text)
                    .frame(width: 14, height: 14)
                    .background(AIMColors.window)
                    .modifier(Bevel.raised)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.vertical, 1)
        .background(AIMColors.field)
        .modifier(Bevel.sunken)
    }
}

/// The window shown while away: your message, the replies that came in, and I'm Back.
struct AwayWindowView: View {
    let app: AppController
    let message: RichTextController
    let onBack: () -> Void
    let onHideWindows: (Bool) -> Void
    let onOpenChat: (UUID) -> Void
    private let sort = State(initialValue: AwaySort.name)

    init(app: AppController, message: RichTextController, onBack: @escaping () -> Void,
         onHideWindows: @escaping (Bool) -> Void, onOpenChat: @escaping (UUID) -> Void) {
        self.app = app
        self.message = message
        self.onBack = onBack
        self.onHideWindows = onHideWindows
        self.onOpenChat = onOpenChat
    }

    var body: some View {
        let away = app.away
        VStack(alignment: .leading, spacing: 8) {
            Text("Your buddies keep working while you're away. Their replies are counted below; nothing is sent to them.")
                .font(AIMFonts.label)
                .fixedSize(horizontal: false, vertical: true)
            RichTextView(controller: message, editable: false)
                .frame(height: 96)
                .modifier(Bevel.sunken)
            Text(Self.summary(away))
                .font(AIMFonts.label)
            tallyList(away)
            Text("Click the 'I'm Back' button to quit being Away").font(AIMFonts.label)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 5) {
                    AIMCheckbox("Hide windows while I'm Away", isOn: Binding(
                        get: { app.away?.hideWindows ?? false },
                        set: { app.setAwayOptions(hideWindows: $0); onHideWindows($0) }))
                    AIMCheckbox("Disable sounds while I'm Away", isOn: Binding(
                        get: { app.away?.muteSounds ?? false },
                        set: { app.setAwayOptions(muteSounds: $0) }))
                }
                Spacer()
                Button("I'm Back", action: onBack)
                    .buttonStyle(AIMButtonStyle(isDefault: true))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(10)
        .frame(width: 380)
        .background(AIMColors.window)
    }

    static func summary(_ away: AwayStatus?) -> String {
        let n = away?.messageCount ?? 0, p = away?.peopleCount ?? 0
        return "\(n) message\(n == 1 ? "" : "s") received from \(p) \(p == 1 ? "person" : "people") while being Away"
    }

    private static let columns: [(AwaySort, String, CGFloat?)] = [(.name, "Buddy", nil), (.count, "Messages", 64), (.lastSent, "Last sent", 92)]

    private func tallyList(_ away: AwayStatus?) -> some View {
        let rows = away?.rows(sortedBy: sort.wrappedValue) ?? []
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Self.columns, id: \.1) { key, title, width in
                    Button { sort.wrappedValue = key } label: {
                        Text(title + (sort.wrappedValue == key ? (key == .name ? " ▲" : " ▼") : ""))
                            .font(sort.wrappedValue == key ? AIMFonts.labelBold : AIMFonts.label)
                            .foregroundStyle(AIMColors.text)
                            .lineLimit(1)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .frame(maxWidth: width == nil ? .infinity : width, alignment: .leading)
                            .frame(width: width)
                            .background(AIMColors.window)
                            .modifier(Bevel.raised)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Sort by \(title.lowercased())")
                }
            }
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(rows, id: \.buddyID) { r in
                        HStack(spacing: 0) {
                            Text(r.screenName).frame(maxWidth: .infinity, alignment: .leading)
                            Text("\(r.count)").frame(width: 64, alignment: .leading)
                            Text(Self.when(r.lastSent)).frame(width: 92, alignment: .leading)
                        }
                        .font(AIMFonts.label)
                        .foregroundStyle(AIMColors.text)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { onOpenChat(r.buddyID) }
                        .help("Double-click to open the IM window")
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .frame(height: 96)
        .background(AIMColors.field)
        .modifier(Bevel.sunken)
    }

    /// Today: just the time. Earlier: date and time.
    static func when(_ d: Date) -> String {
        Calendar.current.isDateInToday(d) ? d.formatted(date: .omitted, time: .shortened)
            : d.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }
}
