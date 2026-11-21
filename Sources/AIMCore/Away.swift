import Foundation

/// A saved (or about-to-be-used) away message. `rich` is RTFD from the editor, `text` its plain form.
public struct AwayMessage: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var label: String
    public var rich: Data
    public var text: String

    public init(id: UUID = UUID(), label: String, rich: Data = Data(), text: String) {
        self.id = id
        self.label = label
        self.rich = rich
        self.text = text
    }
}

/// One buddy's replies while you were away.
public struct AwayTally: Equatable, Sendable {
    public var buddyID: UUID
    /// The name when the last reply arrived, so a buddy removed while you're away still shows.
    public var screenName: String
    public var count: Int
    public var lastSent: Date
}

public enum AwaySort: Sendable, CaseIterable {
    case name, count, lastSent
}

/// While you're away, buddies keep working; their replies are counted here. Nothing is sent to Claude.
public struct AwayStatus: Equatable, Sendable {
    public var message: AwayMessage
    public var since: Date
    public var hideWindows = false
    public var muteSounds = false
    public private(set) var tallies: [UUID: AwayTally] = [:]

    public init(message: AwayMessage, since: Date) {
        self.message = message
        self.since = since
    }

    public var messageCount: Int { tallies.values.reduce(0) { $0 + $1.count } }
    public var peopleCount: Int { tallies.count }

    public mutating func record(buddyID: UUID, screenName: String, at date: Date) {
        var t = tallies[buddyID] ?? AwayTally(buddyID: buddyID, screenName: screenName, count: 0, lastSent: date)
        t.screenName = screenName
        t.count += 1
        t.lastSent = date
        tallies[buddyID] = t
    }

    /// Name A→Z; count and last-sent put the most first. Ties fall back to the other keys in that order.
    public func rows(sortedBy key: AwaySort = .name) -> [AwayTally] {
        func byName(_ a: AwayTally, _ b: AwayTally) -> Bool? {
            let c = a.screenName.localizedStandardCompare(b.screenName)
            return c == .orderedSame ? nil : c == .orderedAscending
        }
        func byCount(_ a: AwayTally, _ b: AwayTally) -> Bool? { a.count == b.count ? nil : a.count > b.count }
        func byLast(_ a: AwayTally, _ b: AwayTally) -> Bool? { a.lastSent == b.lastSent ? nil : a.lastSent > b.lastSent }
        let order: [(AwayTally, AwayTally) -> Bool?] = switch key {
        case .name: [byName, byCount, byLast]
        case .count: [byCount, byName, byLast]
        case .lastSent: [byLast, byName, byCount]
        }
        return tallies.values.sorted { a, b in
            for cmp in order { if let r = cmp(a, b) { return r } }
            return a.buddyID.uuidString < b.buddyID.uuidString
        }
    }

    /// AIM's special characters: %d is the date and %t the time you went away.
    public static func expand(_ s: String, at date: Date) -> String {
        let d = date.formatted(date: .numeric, time: .omitted)
        let t = date.formatted(date: .omitted, time: .shortened)
        return s.replacingOccurrences(of: "%d", with: d).replacingOccurrences(of: "%t", with: t)
    }
}
