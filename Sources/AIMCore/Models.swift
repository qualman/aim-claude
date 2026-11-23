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
    /// Away messages kept with "Save for later use", newest last.
    public var savedAwayMessages: [AwayMessage]

    public init(screenName: String? = nil, buddies: [Buddy] = [], signedOn: Bool = false,
                claudePathOverride: String? = nil, savedAwayMessages: [AwayMessage] = []) {
        self.screenName = screenName
        self.buddies = buddies
        self.signedOn = signedOn
        self.claudePathOverride = claudePathOverride
        self.savedAwayMessages = savedAwayMessages
    }

    private enum CodingKeys: String, CodingKey {
        case screenName, buddies, signedOn, claudePathOverride, savedAwayMessages
    }

    /// Files saved before a field existed still load; the field takes its default.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        screenName = try c.decodeIfPresent(String.self, forKey: .screenName)
        buddies = try c.decode([Buddy].self, forKey: .buddies)
        signedOn = try c.decode(Bool.self, forKey: .signedOn)
        claudePathOverride = try c.decodeIfPresent(String.self, forKey: .claudePathOverride)
        savedAwayMessages = try c.decodeIfPresent([AwayMessage].self, forKey: .savedAwayMessages) ?? []
    }

    /// A turn that was in flight when the app quit is never resent; it's marked instead.
    public mutating func markInterruptedTurns() {
        for i in buddies.indices where buddies[i].pendingTurn {
            buddies[i].messages.append(ChatMessage(sender: .error, text: "Interrupted when the app quit."))
            buddies[i].pendingTurn = false
        }
    }
}
