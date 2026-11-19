import Foundation

public enum ClaudeEvent: Equatable, Sendable {
    /// What the buddy is doing right now, e.g. "Reading notes.txt".
    case activity(String)
    /// The whole reply for the turn.
    case reply(String)
    case failure(String)
    /// The CLI lost this buddy's session; a fresh one with this ID replaces it.
    case sessionReset(UUID)
}
