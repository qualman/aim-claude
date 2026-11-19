import Foundation

public enum Sender: String, Codable, Sendable {
    case user, buddy, system, error
}

public struct ChatMessage: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var sender: Sender
    public var text: String
    public var date: Date

    public init(id: UUID = UUID(), sender: Sender, text: String, date: Date = Date()) {
        self.id = id
        self.sender = sender
        self.text = text
        self.date = date
    }
}

public struct Buddy: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var screenName: String
    public var sessionID: UUID
    public var workingDirectory: URL
    public var messages: [ChatMessage]
    public var hasStartedSession: Bool
    public var pendingTurn: Bool

    public init(id: UUID = UUID(), screenName: String, sessionID: UUID = UUID(),
                workingDirectory: URL, messages: [ChatMessage] = [],
                hasStartedSession: Bool = false, pendingTurn: Bool = false) {
        self.id = id
        self.screenName = screenName
        self.sessionID = sessionID
        self.workingDirectory = workingDirectory
        self.messages = messages
        self.hasStartedSession = hasStartedSession
        self.pendingTurn = pendingTurn
    }
}

public struct AppState: Codable, Equatable, Sendable {
    public var screenName: String?
    public var buddies: [Buddy]
    public var signedOn: Bool
    public var claudePathOverride: String?

    public init(screenName: String? = nil, buddies: [Buddy] = [], signedOn: Bool = false,
                claudePathOverride: String? = nil) {
        self.screenName = screenName
        self.buddies = buddies
        self.signedOn = signedOn
        self.claudePathOverride = claudePathOverride
    }

    /// A turn that was in flight when the app quit is never resent; it's marked instead.
    public mutating func markInterruptedTurns() {
        for i in buddies.indices where buddies[i].pendingTurn {
            buddies[i].messages.append(ChatMessage(sender: .error, text: "Interrupted when the app quit."))
            buddies[i].pendingTurn = false
        }
    }
}
