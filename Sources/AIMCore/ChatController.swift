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
    /// The claude path `channel` was built with; a different one (from Preferences) rebuilds it.
    @ObservationIgnored private var channelClaudePath: URL?
    @ObservationIgnored private var tail: Task<Void, Never>?
    @ObservationIgnored private var closed = false

    public init(buddyID: UUID, app: AppController, makeChannel: @escaping @MainActor () -> (any BuddyChanneling)?) {
        self.buddyID = buddyID
        self.app = app
        self.makeChannel = makeChannel
    }

    public var buddy: Buddy? { app.buddy(buddyID) }
    public var messages: [ChatMessage] { buddy?.messages ?? [] }

    public var needsAttention: Bool { !pendingPermissions.isEmpty }

    public static let signedOffDenial = "The AIM user is signed off."
    public static let removedDenial = "The AIM user removed this buddy."

    /// Ends this buddy's session for good: denies open prompts, stops the running claude
    /// process and drops queued turns. Used when the buddy is removed.
    public func close() async {
        closed = true
        denyAllPermissions(Self.removedDenial)
        await channel?.close()
        channel = nil
    }

    /// Returns false when the request was denied on the spot because the user is signed off.
    @discardableResult
    public func addPermission(_ r: PermissionRequest) -> Bool {
        guard app.state.signedOn else {
            onResolvePermission?(r.id, .deny(Self.signedOffDenial))
            append(.system, "Denied because you're signed off: \(r.inputSummary)")
            return false
        }
        pendingPermissions.append(r)
        return true
    }

    /// Denies every open prompt in this chat, e.g. when the user signs off.
    public func denyAllPermissions(_ reason: String) {
        let open = pendingPermissions
        pendingPermissions.removeAll()
        for r in open { onResolvePermission?(r.id, .deny(reason)) }
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
        guard !text.isEmpty, !closed else { return nil }
        append(.user, text)
        app.sounds.play(.sent)
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
        await app.claudeLocated()
        guard !closed else { return }
        if channel == nil || channelClaudePath != app.claudePath {
            channel = makeChannel()
            channelClaudePath = app.claudePath
        }
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
        denyAllPermissions("The turn ended before you answered.")
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
            app.sounds.play(.received)
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
