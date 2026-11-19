import Foundation
import Synchronization
import Testing
@testable import AIMCore

/// Talks to the real claude CLI. Opt in with AIM_LIVE=1 (spends tokens).
@Suite(.enabled(if: ProcessInfo.processInfo.environment["AIM_LIVE"] == "1"))
struct LiveTests {
    @Test func realClaudeReplies() async throws {
        let shell = LoginShell()
        let claude = try ClaudeLocator.locate(override: nil, shell: shell)
        let path = try shell.run("print -r -- $PATH").split(whereSeparator: \.isNewline).last.map(String.init)
        let b = Buddy(screenName: "xX_Claude_Xx", workingDirectory: FileManager.default.temporaryDirectory)
        let c = BuddyChannel(buddy: b, claudePath: claude, mcpConfigPath: nil, launcher: SystemProcessLauncher(basePATH: path))
        var events: [ClaudeEvent] = []
        for await e in await c.send("Reply with exactly the word: pong") { events.append(e) }
        guard case .reply(let text) = events.last else { Issue.record("\(events)"); return }
        #expect(text.lowercased().contains("pong"))
    }
}

@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["AIM_LIVE"] == "1"))
struct LiveChatTests {
    @Test func chatWithToolUseAndMemory() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("aim-live-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "banana".write(to: dir.appendingPathComponent("fruit.txt"), atomically: true, encoding: .utf8)
        let shell = LoginShell()
        let claude = try ClaudeLocator.locate(override: nil, shell: shell)
        let path = try shell.run("print -r -- $PATH").split(whereSeparator: \.isNewline).last.map(String.init)
        let app = AppController(store: StateStore(directory: dir.appendingPathComponent("state")), sounds: SilentSoundPlayer())
        app.signOn(screenName: "SkaterBoi99")
        let b = app.addBuddy(workingDirectory: dir)
        let chat = ChatController(buddyID: b.id, app: app) {
            BuddyChannel(buddy: app.buddy(b.id)!, claudePath: claude, mcpConfigPath: nil, launcher: SystemProcessLauncher(basePATH: path))
        }
        await chat.send("Read fruit.txt and reply with only its contents.")?.value
        #expect(chat.messages.last?.sender == .buddy)
        #expect(chat.messages.last?.text.lowercased().contains("banana") == true)
        await chat.send("What was the fruit again? One word.")?.value
        #expect(chat.messages.last?.text.lowercased().contains("banana") == true)
        #expect(app.buddy(b.id)?.hasStartedSession == true)
    }
}

@Suite(.enabled(if: ProcessInfo.processInfo.environment["AIM_LIVE"] == "1"))
struct LivePermissionTests {
    @Test func promptAllowsThenDenies() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("aim-live-perm-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let shell = LoginShell()
        let claude = try ClaudeLocator.locate(override: nil, shell: shell)
        let path = try shell.run("print -r -- $PATH").split(whereSeparator: \.isNewline).last.map(String.init)
        let broker = PermissionBroker()
        let answer = Mutex<PermissionDecision>(.allow)
        let seen = Mutex<[String]>([])
        await broker.setObserver { r in
            seen.withLock { $0.append(r.inputSummary) }
            let d = answer.withLock { $0 }
            Task { await broker.resolve(r.id, d) }
        }
        let server = MCPServer(broker: broker, configDirectory: dir.appendingPathComponent("mcp"))
        try await server.start()
        defer { server.stop() }
        let b = Buddy(screenName: "xX_Claude_Xx", workingDirectory: dir)
        let c = BuddyChannel(buddy: b, claudePath: claude, mcpConfigPath: try server.configPath(for: b.id),
                             launcher: SystemProcessLauncher(basePATH: path))

        var events: [ClaudeEvent] = []
        for await e in await c.send(#"Use the Bash tool to run exactly: python3 -c "print(6*7)" and reply with only the output."#) { events.append(e) }
        guard case .reply(let r1) = events.last else { Issue.record("\(events)"); return }
        #expect(r1.contains("42"))
        #expect(seen.withLock { $0 }.contains { $0.contains("print(6*7)") })

        answer.withLock { $0 = .deny("The AIM user clicked Deny.") }
        events = []
        for await e in await c.send(#"Use the Bash tool to run exactly: python3 -c "print(7*8)". If it is denied, reply with only the word DENIED."#) { events.append(e) }
        guard case .reply(let r2) = events.last else { Issue.record("\(events)"); return }
        #expect(r2.uppercased().contains("DENIED"))
        #expect(!r2.contains("56"))
    }
}
