import Foundation
import Synchronization
import Testing
@testable import AIMCore

actor FakeChannel: BuddyChanneling {
    var scripts: [[ClaudeEvent]]
    private(set) var sent: [String] = []
    private(set) var closed = false
    init(_ scripts: [[ClaudeEvent]]) { self.scripts = scripts }
    func close() { closed = true }
    func send(_ text: String) -> AsyncStream<ClaudeEvent> {
        sent.append(text)
        let events = scripts.isEmpty ? [] : scripts.removeFirst()
        return AsyncStream { c in
            for e in events { c.yield(e) }
            c.finish()
        }
    }
}

@MainActor
private func setup(_ scripts: [[ClaudeEvent]], channel: Bool = true) -> (AppController, ChatController, StateStore, FakeChannel, RecordingSounds) {
    let store = StateStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("aim-chat-\(UUID().uuidString)"))
    let sounds = RecordingSounds()
    let app = AppController(store: store, sounds: sounds)
    app.signOn(screenName: "SkaterBoi99")
    let b = app.addBuddy(workingDirectory: URL(fileURLWithPath: "/tmp"))
    let fake = FakeChannel(scripts)
    let chat = ChatController(buddyID: b.id, app: app, makeChannel: { channel ? fake : nil })
    return (app, chat, store, fake, sounds)
}

@MainActor @Suite struct ChatControllerTests {
    @Test func sendAppendsUserMessageAndMarksPending() async {
        let (app, chat, _, _, _) = setup([[]])
        let task = chat.send("hello")
        #expect(chat.messages.first?.sender == .user)
        #expect(chat.messages.first?.text == "hello")
        #expect(app.buddy(chat.buddyID)?.pendingTurn == true)
        await task?.value
    }

    @Test func replyAppendsBuddyMessageAndClearsState() async throws {
        let (app, chat, store, _, sounds) = setup([[.activity("Reading a.swift"), .reply("done")]])
        await chat.send("go")?.value
        #expect(chat.messages.map(\.sender) == [.user, .buddy])
        #expect(chat.messages.last?.text == "done")
        #expect(chat.activity == nil)
        let b = try #require(app.buddy(chat.buddyID))
        #expect(!b.pendingTurn)
        #expect(b.hasStartedSession)
        #expect(try store.load().buddies[0].messages.count == 2)
        #expect(sounds.cues.withLock { $0 } == [.buddyIn, .buddyIn, .sent, .received])
    }

    @Test func activityUpdatesStatusLine() async {
        let (_, chat, _, _, _) = setup([])
        chat.apply(.activity("Reading foo.swift"))
        #expect(chat.statusLine == "xX_Claude_Xx is reading foo.swift…")
        chat.apply(.activity("Running: git status"))
        #expect(chat.statusLine == "xX_Claude_Xx is running: git status…")
    }

    @Test func statusLineWhileWaitingWithoutActivity() async {
        let (_, chat, _, _, _) = setup([[]])
        let task = chat.send("hi")
        #expect(chat.statusLine == "xX_Claude_Xx is thinking…")
        await task?.value
    }

    @Test func failureAppendsErrorAndClearsPending() async {
        let (app, chat, _, _, _) = setup([[.failure("claude exited with status 1: boom")]])
        await chat.send("go")?.value
        #expect(chat.messages.last?.sender == .error)
        #expect(chat.messages.last?.text == "claude exited with status 1: boom")
        #expect(app.buddy(chat.buddyID)?.pendingTurn == false)
        #expect(chat.statusLine == nil)
    }

    @Test func blankInputIsIgnored() async {
        let (_, chat, _, fake, _) = setup([])
        #expect(chat.send("   \n ") == nil)
        #expect(chat.messages.isEmpty)
        #expect(await fake.sent.isEmpty)
    }

    @Test func sessionResetStoresNewIDAndNotes() async {
        let newID = UUID()
        let (app, chat, _, _, _) = setup([[.sessionReset(newID), .reply("fresh")]])
        await chat.send("go")?.value
        let b = app.buddy(chat.buddyID)
        #expect(b?.sessionID == newID)
        #expect(chat.messages.contains { $0.sender == .system && $0.text.contains("doesn't remember") })
        #expect(chat.messages.last?.text == "fresh")
    }

    @Test func missingClaudeShowsError() async {
        let (_, chat, _, _, _) = setup([], channel: false)
        await chat.send("hi")?.value
        #expect(chat.messages.last?.sender == .error)
        #expect(chat.messages.last?.text.contains("claude") == true)
    }

    @Test func pendingStaysTrueUntilQueueDrains() async {
        let (app, chat, _, _, _) = setup([[.reply("one")], [.reply("two")]])
        let t1 = chat.send("a")
        let t2 = chat.send("b")
        await t1?.value
        await t2?.value
        #expect(app.buddy(chat.buddyID)?.pendingTurn == false)
        #expect(chat.messages.map(\.text) == ["a", "b", "one", "two"])
    }
}
