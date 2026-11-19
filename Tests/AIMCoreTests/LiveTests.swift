import Foundation
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
