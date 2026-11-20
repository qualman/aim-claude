import AIMCore
import SwiftUI

struct BuddyListActions {
    var openChat: (UUID) -> Void = { _ in }
    var addBuddy: () -> Void = {}
    var signOff: () -> Void = {}
    var changeScreenName: () -> Void = {}
    var preferences: () -> Void = {}
    var getInfo: (UUID) -> Void = { _ in }
    var about: () -> Void = {}
}

struct BuddyListView: View {
    let app: AppController
    let skin: SkinStore
    var attention: Set<UUID> = []
    let actions: BuddyListActions
    private let selection = State<UUID?>(initialValue: nil)
    private let buddiesOpen = State(initialValue: true)

    init(app: AppController, skin: SkinStore, attention: Set<UUID> = [], actions: BuddyListActions) {
        self.app = app
        self.skin = skin
        self.attention = attention
        self.actions = actions
    }

    private var target: UUID? { selection.wrappedValue ?? app.state.buddies.first?.id }

    var body: some View {
        VStack(spacing: 0) {
            MenuStrip {
                StripMenu(title: "MyAIM") {
                    Button("Add Buddy…", action: actions.addBuddy)
                    Button("Change Screen Name…", action: actions.changeScreenName)
                    Button("Preferences…", action: actions.preferences)
                    Divider()
                    Button("Sign Off", action: actions.signOff)
                }
                StripMenu(title: "People") {
                    Button("Send Instant Message") { if let t = target { actions.openChat(t) } }
                        .disabled(target == nil)
                    Button("Get Buddy Info") { if let t = target { actions.getInfo(t) } }
                        .disabled(target == nil)
                }
                StripMenu(title: "Help") {
                    Button("About AIM", action: actions.about)
                }
            }
            EtchedRule()
            banner.padding(.vertical, 6)
            tabs
            list
            toolbar
        }
        .background(AIMColors.window)
        .frame(minWidth: 210, minHeight: 380)
    }

    private var banner: some View {
        Group {
            if Skin.image("buddylist-banner") != nil {
                SkinIcon(name: "buddylist-banner")
            } else {
                HStack(spacing: 6) {
                    AIMLogo(skin: skin).frame(width: 34, height: 40)
                    Text("Instant Messenger").font(AIMFonts.labelBold).foregroundStyle(.white)
                }
                .padding(8)
                .background(AIMColors.titleBlue)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var tabs: some View {
        HStack(alignment: .bottom, spacing: 0) {
            Text("Online").font(AIMFonts.labelBold)
                .padding(.horizontal, 10).padding(.top, 4).padding(.bottom, 3)
                .background(AIMColors.window)
                .modifier(Bevel.raised)
            Text("List Setup").font(AIMFonts.label)
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(AIMColors.window)
                .modifier(Bevel.raised)
            Spacer()
        }
        .padding(.horizontal, 6)
    }

    private var list: some View {
        let n = app.state.buddies.count
        return ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                groupRow(open: buddiesOpen.wrappedValue, title: "Buddies (\(n)/\(n))") { buddiesOpen.wrappedValue.toggle() }
                if buddiesOpen.wrappedValue {
                    ForEach(app.state.buddies) { b in buddyRow(b) }
                }
                groupRow(open: true, title: "Family (0/0)") {}
                groupRow(open: true, title: "Co-workers (0/0)") {}
                groupRow(open: true, title: "Offline (0/0)") {}
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AIMColors.field)
        .modifier(Bevel.sunken)
        .padding(.horizontal, 6)
    }

    private func groupRow(open: Bool, title: String, toggle: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Group {
                if Skin.image("tree-open") != nil {
                    SkinIcon(name: "tree-open").rotationEffect(.degrees(open ? 0 : -90))
                } else {
                    Image(systemName: open ? "arrowtriangle.down.fill" : "arrowtriangle.right.fill").font(.system(size: 7))
                }
            }
            .frame(width: 9)
            Text(title).font(AIMFonts.labelBold)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
    }

    private func buddyRow(_ b: Buddy) -> some View {
        let selected = selection.wrappedValue == b.id
        return HStack(spacing: 4) {
            Text(b.screenName).font(AIMFonts.label)
                .foregroundStyle(selected ? Color.white : AIMColors.text)
                .padding(.horizontal, 2)
                .background(selected ? AIMColors.selection : Color.clear)
            if attention.contains(b.id) {
                Image(systemName: "exclamationmark.bubble.fill").font(.system(size: 10)).foregroundStyle(AIMColors.error)
            }
        }
        .padding(.leading, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { actions.openChat(b.id) }
        .onTapGesture { selection.wrappedValue = b.id }
        .help(b.workingDirectory.path)
    }

    private var toolbar: some View {
        HStack(spacing: 6) {
            SkinButton(icon: "buddylist-im", title: "Send Instant Message", fallback: "bubble.left") {
                if let t = target { actions.openChat(t) }
            }
            SkinButton(icon: "add-small", title: "Add Buddy", fallback: "person.badge.plus", action: actions.addBuddy)
            SkinButton(icon: "runner-small", title: "Sign Off", fallback: "door.left.hand.open", action: actions.signOff)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}
