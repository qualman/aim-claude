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
