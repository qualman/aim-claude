import AIMCore
import SwiftUI

struct BuddyListView: View {
    let app: AppController
    let skin: SkinStore
    let onOpenChat: (UUID) -> Void
    let onAddBuddy: () -> Void
    let onSignOff: () -> Void
    var attention: Set<UUID> = []
    private let selection = State<UUID?>(initialValue: nil)
    private let buddiesOpen = State(initialValue: true)

    init(app: AppController, skin: SkinStore, attention: Set<UUID> = [], onOpenChat: @escaping (UUID) -> Void,
         onAddBuddy: @escaping () -> Void, onSignOff: @escaping () -> Void) {
        self.app = app
        self.skin = skin
        self.attention = attention
        self.onOpenChat = onOpenChat
        self.onAddBuddy = onAddBuddy
        self.onSignOff = onSignOff
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            tabs
            list
            toolbar
        }
        .background(AIMColors.window)
        .frame(minWidth: 200, minHeight: 360)
    }

    private var header: some View {
        HStack(spacing: 8) {
            AIMLogo(skin: skin).frame(width: 34, height: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(app.state.screenName ?? "")'s Buddy List").font(AIMFonts.labelBold).lineLimit(1)
                Text("Online").font(AIMFonts.small).foregroundStyle(AIMColors.shadow)
            }
            Spacer(minLength: 0)
        }
        .padding(6)
        .frame(maxWidth: .infinity)
        .background(LinearGradient(colors: [Color(white: 0.98), AIMColors.window], startPoint: .top, endPoint: .bottom))
        .bevelRaised()
        .padding(4)
    }

    private var tabs: some View {
        HStack(spacing: 0) {
            Text("Online").font(AIMFonts.labelBold).padding(.horizontal, 10).padding(.vertical, 3)
                .background(AIMColors.window).bevelRaised()
            Text("List Setup").font(AIMFonts.label).foregroundStyle(AIMColors.shadow)
                .padding(.horizontal, 10).padding(.vertical, 2)
            Spacer()
        }
        .padding(.horizontal, 6)
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                groupRow(open: buddiesOpen.wrappedValue,
                         title: "Buddies (\(app.state.buddies.count)/\(app.state.buddies.count))") {
                    buddiesOpen.wrappedValue.toggle()
                }
                if buddiesOpen.wrappedValue {
                    ForEach(app.state.buddies) { b in buddyRow(b) }
                }
                groupRow(open: false, title: "Offline (0/0)") {}
            }
            .padding(4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AIMColors.field)
        .bevelSunken()
        .padding(.horizontal, 6)
        .padding(.bottom, 4)
    }

    private func groupRow(open: Bool, title: String, toggle: @escaping () -> Void) -> some View {
        HStack(spacing: 3) {
            Image(systemName: open ? "arrowtriangle.down.fill" : "arrowtriangle.right.fill").font(.system(size: 7))
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
        .padding(.leading, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onOpenChat(b.id) }
        .onTapGesture { selection.wrappedValue = b.id }
        .help(b.workingDirectory.path)
    }

    private var toolbar: some View {
        HStack(spacing: 3) {
            AIMToolbarButton(title: "IM", symbol: "bubble.left.and.text.bubble.right") {
                if let id = selection.wrappedValue ?? app.state.buddies.first?.id { onOpenChat(id) }
            }
            AIMToolbarButton(title: "Add", symbol: "person.badge.plus", action: onAddBuddy)
            AIMToolbarButton(title: "Sign Off", symbol: "door.left.hand.open", action: onSignOff)
        }
        .padding(6)
    }
}
