import Foundation
import Testing
@testable import AIMCore

private func tempDir() -> URL {
    let u = FileManager.default.temporaryDirectory.appendingPathComponent("aim-tests-\(UUID().uuidString)")
    return u
}

private func buddy(_ name: String, pending: Bool = false) -> Buddy {
    Buddy(id: UUID(), screenName: name, sessionID: UUID(),
          workingDirectory: URL(fileURLWithPath: "/tmp"), messages: [],
          hasStartedSession: false, pendingTurn: pending)
}

@Suite struct BuddyNamerTests {
    @Test func firstNameHasNoNumber() {
        #expect(BuddyNamer.nextName(existing: []) == "xX_Claude_Xx")
    }
    @Test func secondIsTwo() {
        #expect(BuddyNamer.nextName(existing: ["xX_Claude_Xx"]) == "xX_Claude2_Xx")
    }
    @Test func continuesSequence() {
        #expect(BuddyNamer.nextName(existing: ["xX_Claude_Xx", "xX_Claude2_Xx", "xX_Claude3_Xx"]) == "xX_Claude4_Xx")
    }
    @Test func fillsGap() {
        #expect(BuddyNamer.nextName(existing: ["xX_Claude_Xx", "xX_Claude3_Xx"]) == "xX_Claude2_Xx")
    }
}

@Suite struct StateStoreTests {
    @Test func roundTrips() throws {
        let store = StateStore(directory: tempDir())
        var s = AppState()
        s.screenName = "SkaterBoi99"
        s.signedOn = true
        s.buddies = [buddy("xX_Claude_Xx"), buddy("xX_Claude2_Xx")]
        s.buddies[0].messages = [ChatMessage(id: UUID(), sender: .user, text: "hi", date: Date(timeIntervalSince1970: 1000))]
        try store.save(s)
        #expect(try store.load() == s)
    }
    @Test func emptyDirectoryLoadsDefault() throws {
        let s = try StateStore(directory: tempDir()).load()
        #expect(s.screenName == nil)
        #expect(s.buddies.isEmpty)
        #expect(s.signedOn == false)
    }
    @Test func corruptFileThrowsAndIsUntouched() throws {
        let dir = tempDir()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("state.json")
        try Data("{not json".utf8).write(to: file)
        #expect(throws: (any Error).self) { try StateStore(directory: dir).load() }
        #expect(try String(contentsOf: file, encoding: .utf8) == "{not json")
    }
}

@Suite struct InterruptedTurnTests {
    @Test func marksPendingTurnsInterrupted() {
        var s = AppState()
        s.buddies = [buddy("a", pending: true), buddy("b")]
        s.markInterruptedTurns()
        #expect(s.buddies[0].pendingTurn == false)
        #expect(s.buddies[0].messages.last?.sender == .error)
        #expect(s.buddies[0].messages.last?.text == "Interrupted when the app quit.")
        #expect(s.buddies[1].messages.isEmpty)
    }
}
