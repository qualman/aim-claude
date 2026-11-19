import Foundation
import Observation

/// One buddy's conversation: sends messages, shows activity, records replies in app state.
@MainActor @Observable
public final class ChatController {
    public let buddyID: UUID
    /// The latest activity, e.g. "Reading foo.swift"; nil when idle.
    public private(set) var activity: String?
    /// Turns sent but not yet answered.
    public private(set) var inFlight = 0
    /// Tool calls waiting for Allow / Deny in this chat.
    public private(set) var pendingPermissions: [PermissionRequest] = []
    @ObservationIgnored public var onReply: (() -> Void)?
    @ObservationIgnored public var onTurnEnded: (() -> Void)?
    @ObservationIgnored public var onResolvePermission: ((UUID, PermissionDecision) -> Void)?

    @ObservationIgnored private let app: AppController
    @ObservationIgnored private let makeChannel: @MainActor () -> (any BuddyChanneling)?
    @ObservationIgnored private var channel: (any BuddyChanneling)?
    @ObservationIgnored private var tail: Task<Void, Never>?

    public init(buddyID: UUID, app: AppController, makeChannel: @escaping @MainActor () -> (any BuddyChanneling)?) {
        self.buddyID = buddyID
        self.app = app
        self.makeChannel = makeChannel
    }

    public var buddy: Buddy? { app.buddy(buddyID) }
    public var messages: [ChatMessage] { buddy?.messages ?? [] }

    public var needsAttention: Bool { !pendingPermissions.isEmpty }

    public func addPermission(_ r: PermissionRequest) {
        pendingPermissions.append(r)
    }

    public func resolvePermission(_ id: UUID, allow: Bool) {
        guard let r = pendingPermissions.first(where: { $0.id == id }) else { return }
        pendingPermissions.removeAll { $0.id == id }
        onResolvePermission?(id, allow ? .allow : .deny("The AIM user clicked Deny."))
        let verb = allow ? "allowed" : "denied"
        append(.system, "You \(verb): \(r.inputSummary)")
    }

    public var statusLine: String? {
        let name = buddy?.screenName ?? "Buddy"
        if let a = activity { return "\(name) is \(a.prefix(1).lowercased() + a.dropFirst())…" }
        return inFlight > 0 ? "\(name) is thinking…" : nil
    }

    /// Returns the task for the turn (tests await it), or nil for blank input.
    @discardableResult
    public func send(_ raw: String) -> Task<Void, Never>? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        append(.user, text)
        inFlight += 1
        app.updateBuddy(buddyID) { $0.pendingTurn = true }
        let previous = tail
        let task = Task { @MainActor in
            await previous?.value
            await self.run(text)
            self.inFlight -= 1
            if self.inFlight == 0 {
                self.activity = nil
                self.app.updateBuddy(self.buddyID) { $0.pendingTurn = false }
            }
        }
        tail = task
        return task
    }

    private func run(_ text: String) async {
        if channel == nil { channel = makeChannel() }
        guard let channel else {
            append(.error, "AIM couldn't find the claude command, so this message wasn't sent.")
            return
        }
        for await event in await channel.send(text) {
            apply(event)
        }
        activity = nil
        endTurn()
    }

    /// Any prompt still open belongs to a turn that's over; answering it later would do nothing.
    private func endTurn() {
        let open = pendingPermissions
        pendingPermissions.removeAll()
        for r in open { onResolvePermission?(r.id, .deny("The turn ended before you answered.")) }
        onTurnEnded?()
    }

    public func apply(_ event: ClaudeEvent) {
        switch event {
        case .activity(let a):
            activity = a
        case .reply(let text):
            activity = nil
            append(.buddy, text)
            app.updateBuddy(buddyID) { $0.hasStartedSession = true }
            app.sounds.play(.message)
            onReply?()
        case .failure(let message):
            activity = nil
            append(.error, message)
        case .sessionReset(let id):
            app.updateBuddy(buddyID) {
                $0.sessionID = id
                $0.hasStartedSession = false
            }
            append(.system, "\(buddy?.screenName ?? "Your buddy")'s Claude session was lost, so it started a new one. It doesn't remember the conversation above.")
        }
    }

    private func append(_ sender: Sender, _ text: String) {
        app.updateBuddy(buddyID) { $0.messages.append(ChatMessage(sender: sender, text: text)) }
    }
}
