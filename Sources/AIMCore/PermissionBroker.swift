import Foundation

public struct PermissionRequest: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var buddyID: UUID
    public var toolName: String
    /// Human-readable, e.g. "Running: git push".
    public var inputSummary: String

    public init(id: UUID, buddyID: UUID, toolName: String, inputSummary: String) {
        self.id = id
        self.buddyID = buddyID
        self.toolName = toolName
        self.inputSummary = inputSummary
    }
}

public enum PermissionDecision: Equatable, Sendable {
    case allow
    case deny(String)
}

/// Holds tool-permission requests from claude until the user answers them in a chat window.
public actor PermissionBroker {
    private var waiting: [UUID: (PermissionRequest, CheckedContinuation<PermissionDecision, Never>)] = [:]
    private var order: [UUID] = []
    private var observer: (@Sendable (PermissionRequest) -> Void)?
    private var closed = false

    public init() {}

    public var pending: [PermissionRequest] { order.compactMap { waiting[$0]?.0 } }

    public func setObserver(_ observer: @escaping @Sendable (PermissionRequest) -> Void) {
        self.observer = observer
    }

    public func request(_ r: PermissionRequest) async -> PermissionDecision {
        if closed { return .deny("App closed") }
        return await withCheckedContinuation { cont in
            waiting[r.id] = (r, cont)
            order.append(r.id)
            observer?(r)
        }
    }

    public func resolve(_ id: UUID, _ decision: PermissionDecision) {
        guard let (_, cont) = waiting.removeValue(forKey: id) else { return }
        order.removeAll { $0 == id }
        cont.resume(returning: decision)
    }

    public func shutdown() {
        closed = true
        for id in order { resolve(id, .deny("App closed")) }
    }
}
