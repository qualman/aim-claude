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
    private let selection: State<UUID?>
    private let buddiesOpen = State(initialValue: true)

    init(app: AppController, skin: SkinStore, attention: Set<UUID> = [], selected: UUID? = nil,
         actions: BuddyListActions) {
        self.app = app
        self.skin = skin
        self.attention = attention
        self.selection = State(initialValue: selected)
        self.actions = actions
    }

    /// The selected buddy. Nothing is selected after a click on empty space, and IM / Info then do nothing.
    private var target: UUID? { selection.wrappedValue.flatMap { id in app.state.buddies.contains { $0.id == id } ? id : nil } }

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
            tabPanel
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

    /// Win98 tab control: the Online tab joins a raised panel that holds the list and the toolbar.
    private var tabPanel: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 0) {
                Text("Online").font(AIMFonts.labelBold)
                    .padding(.horizontal, 10).padding(.top, 4).padding(.bottom, 5)
                    .background(AIMColors.window)
                    .overlay(TabEdges())
                    // Reaches 2 pt into the panel, covering its top edge so the tab and panel read as one.
                    .padding(.bottom, -2)
                    .zIndex(1)
                Text("List Setup").font(AIMFonts.label)
                    .padding(.horizontal, 7).padding(.top, 2).padding(.bottom, 2)
                    .background(AIMColors.window)
                    .overlay(TabEdges())
                Spacer()
            }
            .zIndex(1)
            VStack(spacing: 4) {
                list
                toolbar
            }
            .padding(.top, 6).padding(.horizontal, 6)
            .background(AIMColors.window)
            .modifier(Bevel.raised)
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 6)
    }

    private var list: some View {
        let n = app.state.buddies.count
        return GeometryReader { geo in ScrollView {
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
            // Fill the visible area so a click anywhere below the rows lands here and clears the selection.
            .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .onTapGesture { selection.wrappedValue = nil }
        } }
        .background(AIMColors.field)
        .modifier(Bevel.sunken)
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
        HStack(alignment: .center, spacing: 12) {
            SkinButton(icon: "buddylist-im", title: "Send Instant Message", fallback: "bubble.left") {
                if let t = target { actions.openChat(t) }
            }
            .disabled(target == nil)
            SkinButton(icon: "add-small", title: "Add Buddy", fallback: "person.badge.plus", action: actions.addBuddy)
            SkinButton(icon: "buddylist-info", title: "Get Buddy Info", fallback: "person.text.rectangle") {
                if let t = target { actions.getInfo(t) }
            }
            .disabled(target == nil)
            Spacer()
        }
        .frame(height: 30)
        .padding(.horizontal, 4)
    }
}

/// A Win98 tab's raised edges on the top and sides, open at the bottom.
private struct TabEdges: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            func line(_ x: CGFloat, _ y: CGFloat, _ lw: CGFloat, _ lh: CGFloat, _ c: Color) {
                ctx.fill(Path(CGRect(x: x, y: y, width: lw, height: lh)), with: .color(c))
            }
            line(0, 2, 1, h - 2, AIMColors.highlight)        // left
            line(1, 1, 1, 1, AIMColors.highlight)            // rounded corner
            line(2, 0, w - 4, 1, AIMColors.highlight)        // top
            line(1, 2, 1, h - 2, AIMColors.light)
            line(2, 1, w - 4, 1, AIMColors.light)
            line(w - 1, 2, 1, h - 2, AIMColors.darkShadow)   // right
            line(w - 2, 1, 1, 1, AIMColors.darkShadow)
            line(w - 2, 2, 1, h - 2, AIMColors.shadow)
        }
        .allowsHitTesting(false)
    }
}
