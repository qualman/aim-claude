import Foundation
import Synchronization
import Testing
@testable import AIMCore

private func collect(_ s: AsyncStream<ClaudeEvent>) async -> [ClaudeEvent] {
    var out: [ClaudeEvent] = []
    for await e in s { out.append(e) }
    return out
}

private func drain(_ p: any RunningProcess) async -> Error? {
    do { for try await _ in p.lines {} ; return nil } catch { return error }
}

@Suite struct ReviewFixChannelTests {
    // Review #1: a turn waiting on Allow/Deny must not be killed by the inactivity watchdog.
    @Test func watchdogWaitsWhileUserIsDeciding() async throws {
        let p = FakeProcess(lines: [], hang: true)
        let c = BuddyChannel(buddy: Buddy(screenName: "x", workingDirectory: URL(fileURLWithPath: "/tmp")),
                             claudePath: URL(fileURLWithPath: "/usr/bin/true"), mcpConfigPath: nil,
                             launcher: FakeLauncher([p]), inactivityTimeout: .milliseconds(150),
                             permissionPending: { true })
        let events = Task { await collect(await c.send("x")) }
        try await Task.sleep(for: .milliseconds(700))
        #expect(!p.terminated.withLock { $0 })
        p.terminate()
        _ = await events.value
    }

    // Review #6: inactivity limit must exceed the CLI's 10-minute max tool runtime.
    @Test func defaultTimeoutOutlastsLongestTool() {
        #expect(BuddyChannel.defaultInactivityTimeout > .seconds(600))
    }

    // Review #4: session loss reported only in result.errors (stderr empty) still resets.
    @Test func sessionLostDetectedFromResultErrors() async {
        let bad = #"{"type":"result","subtype":"error_during_execution","is_error":true,"result":"","errors":["No conversation found with session ID: abc"]}"#
        let ok = #"{"type":"result","subtype":"success","is_error":false,"result":"fresh"}"#
        let l = FakeLauncher([FakeProcess(lines: [bad], status: 1, stderr: ""), FakeProcess(lines: [ok])])
        let c = BuddyChannel(buddy: Buddy(screenName: "x", workingDirectory: URL(fileURLWithPath: "/tmp"), hasStartedSession: true),
                             claudePath: URL(fileURLWithPath: "/usr/bin/true"), mcpConfigPath: nil, launcher: l)
        let e = await collect(await c.send("x"))
        guard case .sessionReset = e.first else { Issue.record("\(e)"); return }
        #expect(e.last == .reply("fresh"))
    }

    // Review #4: on non-zero exit, show claude's own error text, not just stderr.
    @Test func nonZeroExitIncludesResultErrors() async {
        let bad = #"{"type":"result","subtype":"error_during_execution","is_error":true,"result":"","errors":["Model overloaded"]}"#
        let l = FakeLauncher([FakeProcess(lines: [bad], status: 1, stderr: "")])
        let c = BuddyChannel(buddy: Buddy(screenName: "x", workingDirectory: URL(fileURLWithPath: "/tmp")),
                             claudePath: URL(fileURLWithPath: "/usr/bin/true"), mcpConfigPath: nil, launcher: l)
        let e = await collect(await c.send("x"))
        guard case .failure(let msg) = e.last else { Issue.record("\(e)"); return }
        #expect(msg.contains("Model overloaded"))
    }
}

@Suite(.serialized) struct SystemProcessTests {
    private let launcher = SystemProcessLauncher(basePATH: "/usr/bin:/bin")

    // Review #4: stderr written right before exit is not lost.
    @Test func capturesStderrOnExit() async {
        let p = launcher.launch(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "echo late-error >&2; exit 3"],
                                workingDirectory: URL(fileURLWithPath: "/tmp"), environment: [:], stdin: "")
        let err = await drain(p) as? ProcessFailure
        #expect(err?.status == 3)
        #expect(err?.stderrTail == "late-error")
    }

    // Review #8: a big message to a process that exits without reading must not crash the app.
    @Test func largeStdinToExitedProcessDoesNotCrash() async {
        let p = launcher.launch(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "exit 0"],
                                workingDirectory: URL(fileURLWithPath: "/tmp"), environment: [:],
                                stdin: String(repeating: "x", count: 1_000_000))
        _ = await drain(p)
    }

    // Review #5: quitting the app stops in-flight claude processes.
    @Test func terminateAllStopsLiveProcesses() async {
        let p = launcher.launch(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"],
                                workingDirectory: URL(fileURLWithPath: "/tmp"), environment: [:], stdin: "")
        try? await Task.sleep(for: .milliseconds(200))
        SystemProcessLauncher.terminateAll()
        let started = ContinuousClock.now
        _ = await drain(p)
        #expect(ContinuousClock.now - started < .seconds(5))
    }
}

@Suite struct ReviewFixPermissionTests {
    // Review #2: when a turn ends, that buddy's open requests are denied, others untouched.
    @Test func cancelAllForBuddyDeniesOnlyThatBuddy() async {
        let broker = PermissionBroker()
        let a = UUID(), b = UUID()
        let ra = PermissionRequest(id: UUID(), buddyID: a, toolName: "Bash", inputSummary: "x")
        let rb = PermissionRequest(id: UUID(), buddyID: b, toolName: "Bash", inputSummary: "y")
        async let da = broker.request(ra)
        async let db = broker.request(rb)
        for _ in 0..<200 where await broker.pending.count < 2 { try? await Task.sleep(for: .milliseconds(10)) }
        await broker.cancelAll(buddyID: a)
        #expect(await da == .deny("The turn ended before you answered."))
        #expect(await broker.pending.map(\.id) == [rb.id])
        await broker.resolve(rb.id, .allow)
        _ = await db
    }

    // Review #3: the approval shows the whole command and full path.
    @Test func permissionSummaryIsComplete() {
        let cmd = "cd build && make all && " + String(repeating: "x", count: 120) + "\nrm -rf out"
        #expect(EventParser.permissionSummary(tool: "Bash", input: ["command": cmd]) == "Run: \(cmd)")
        #expect(EventParser.permissionSummary(tool: "Edit", input: ["file_path": "/a/b/config.json"]) == "Edit /a/b/config.json")
        let other = EventParser.permissionSummary(tool: "mcp__x__send", input: ["to": "bob"])
        #expect(other.contains("mcp__x__send") && other.contains("bob"))
    }

    // Review #7: a bad Content-Length is rejected, not a crash.
    @Test func negativeContentLengthIsRejected() {
        var buf = Data("POST /x HTTP/1.1\r\nContent-Length: -1\r\n\r\n".utf8)
        let parsed = MCPServer.parse(&buf)
        #expect(parsed?.0.method == "BAD")
        var huge = Data("POST /x HTTP/1.1\r\nContent-Length: 999999999\r\n\r\n".utf8)
        #expect(MCPServer.parse(&huge)?.0.method == "BAD")
    }
}

@MainActor @Suite struct ReviewFixChatTests {
    private func setup(_ scripts: [[ClaudeEvent]]) -> (AppController, ChatController) {
        let store = StateStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("aim-rf-\(UUID().uuidString)"))
        let app = AppController(store: store, sounds: SilentSoundPlayer())
        let b = app.addBuddy(workingDirectory: URL(fileURLWithPath: "/tmp"))
        let fake = FakeChannel(scripts)
        return (app, ChatController(buddyID: b.id, app: app) { fake })
    }

    // Review #2: a turn that ends leaves no live Allow/Deny panel and claims nothing ran.
    @Test func turnEndClearsUnansweredPermissions() async {
        let (_, chat) = setup([[.failure("Timed out")]])
        let resolved = Mutex<[PermissionDecision]>([])
        chat.onResolvePermission = { _, d in resolved.withLock { $0.append(d) } }
        chat.addPermission(PermissionRequest(id: UUID(), buddyID: chat.buddyID, toolName: "Bash", inputSummary: "Run: ls"))
        await chat.send("go")?.value
        #expect(chat.pendingPermissions.isEmpty)
        #expect(!chat.needsAttention)
        #expect(!chat.messages.contains { $0.text.contains("You allowed") })
        #expect(resolved.withLock { $0 } == [.deny("The turn ended before you answered.")])
    }

    // Review #13: a reply tells the window layer so it can pop the IM open, as AIM did.
    @Test func replyNotifiesListener() async {
        let (_, chat) = setup([[.reply("hi")]])
        let replies = Mutex(0)
        chat.onReply = { replies.withLock { $0 += 1 } }
        await chat.send("go")?.value
        #expect(replies.withLock { $0 } == 1)
    }
}
