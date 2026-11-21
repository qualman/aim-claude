import Foundation
import Synchronization
import Testing
@testable import AIMCore

private func store() -> StateStore {
    StateStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("aim-remove-\(UUID().uuidString)"))
}

@MainActor @Suite struct RemoveBuddyTests {
    @Test func removeDropsBuddyPersistsAndPlaysDoorClose() throws {
        let s = store()
        let sounds = RecordingSounds()
        let app = AppController(store: s, sounds: sounds)
        app.signOn(screenName: "SkaterBoi99")
        let a = app.addBuddy(workingDirectory: URL(fileURLWithPath: "/tmp"))
        let b = app.addBuddy(workingDirectory: URL(fileURLWithPath: "/tmp"))
        app.removeBuddy(a.id)
        #expect(app.state.buddies.map(\.id) == [b.id])
        #expect(try s.load().buddies.map(\.id) == [b.id])
        #expect(sounds.cues.withLock { $0.last } == .buddyOut)
    }

    @Test func removingUnknownBuddyDoesNothing() {
        let sounds = RecordingSounds()
        let app = AppController(store: store(), sounds: sounds)
        app.signOn(screenName: "SkaterBoi99")
        let before = sounds.cues.withLock { $0.count }
        app.removeBuddy(UUID())
        #expect(sounds.cues.withLock { $0.count } == before)
    }

    @Test func closeDeniesPromptsClosesChannelAndRefusesSends() async {
        let app = AppController(store: store(), sounds: SilentSoundPlayer())
        app.signOn(screenName: "SkaterBoi99")
        let b = app.addBuddy(workingDirectory: URL(fileURLWithPath: "/tmp"))
        let fake = FakeChannel([[.reply("hi")]])
        let chat = ChatController(buddyID: b.id, app: app) { fake }
        let denied = Mutex<[PermissionDecision]>([])
        chat.onResolvePermission = { _, d in denied.withLock { $0.append(d) } }
        await chat.send("hello")?.value  // builds the channel
        chat.addPermission(PermissionRequest(id: UUID(), buddyID: b.id, toolName: "Bash", inputSummary: "Run: ls"))

        await chat.close()

        #expect(denied.withLock { $0 } == [.deny(ChatController.removedDenial)])
        #expect(!chat.needsAttention)
        #expect(await fake.closed)
        #expect(chat.send("still there?") == nil)
        #expect(await fake.sent == ["hello"])
    }
}

@Suite struct ChannelCloseTests {
    @Test func closeKillsRunningTurnQuietlyAndSkipsQueuedOnes() async throws {
        let hung = FakeProcess(lines: [], hang: true)
        let launcher = FakeLauncher([hung, FakeProcess(lines: [])])
        let ch = BuddyChannel(buddy: Buddy(screenName: "xX_Claude_Xx", workingDirectory: URL(fileURLWithPath: "/tmp")),
                              claudePath: URL(fileURLWithPath: "/usr/bin/true"), mcpConfigPath: nil, launcher: launcher)
        let first = await ch.send("long job")
        let second = await ch.send("queued")
        for _ in 0..<200 where launcher.launches.withLock({ $0.count }) == 0 { try await Task.sleep(for: .milliseconds(5)) }

        await ch.close()

        var events: [ClaudeEvent] = []
        for await e in first { events.append(e) }
        for await e in second { events.append(e) }
        #expect(hung.terminated.withLock { $0 })
        #expect(events.isEmpty)  // no "claude exited with status 15"
        #expect(launcher.launches.withLock { $0.count } == 1)
        let after = await ch.send("after close")
        for await _ in after {}
        #expect(launcher.launches.withLock { $0.count } == 1)
    }
}
