public enum ClaudeEvent: Equatable, Sendable {
    /// What the buddy is doing right now, e.g. "Reading notes.txt".
    case activity(String)
    /// The whole reply for the turn.
    case reply(String)
    case failure(String)
}
