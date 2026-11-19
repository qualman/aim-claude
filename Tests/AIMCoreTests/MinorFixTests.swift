import Foundation
import Synchronization
import Testing
@testable import AIMCore

/// A thread-safe list that, unlike `Mutex`, can be returned in a tuple.
private final class Recorded<T: Sendable>: @unchecked Sendable {
    private let items = Mutex<[T]>([])
    func add(_ t: T) { items.withLock { $0.append(t) } }
    var all: [T] { items.withLock { $0 } }
}

private func tempDir(_ tag: String) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("aim-\(tag)-\(UUID().uuidString)")
}

// MARK: #9 sends before claude is located; path changes reach existing chats

@MainActor @Suite struct ClaudeLocationTests {
    private func setup() -> (AppController, ChatController, Recorded<URL?>) {
        let app = AppController(store: StateStore(directory: tempDir("loc")), sounds: SilentSoundPlayer())
        app.signOn(screenName: "SkaterBoi99")
        let b = app.addBuddy(workingDirectory: URL(fileURLWithPath: "/tmp"))
        let made = Recorded<URL?>()
        // Like WindowManager: no channel until claude's path is known.
        let chat = ChatController(buddyID: b.id, app: app) {
            made.add(app.claudePath)
            return app.claudePath == nil ? nil : FakeChannel([[.reply("hi")], [.reply("hi again")]])
        }
        return (app, chat, made)
    }

    @Test func sendWaitsForLookupInsteadOfFailing() async throws {
        let (app, chat, _) = setup()
        app.beginLocatingClaude()
        let turn = chat.send("hello")
        try await Task.sleep(for: .milliseconds(100))
        #expect(!chat.messages.contains { $0.sender == .error })
        app.applyLocatorResult(.success(URL(fileURLWithPath: "/usr/bin/true")))
        await turn?.value
        #expect(chat.messages.last?.sender == .buddy)
        #expect(!chat.messages.contains { $0.sender == .error })
    }

    @Test func lookupFailureStillReportsMissingClaude() async {
        let (app, chat, _) = setup()
        app.beginLocatingClaude()
        let turn = chat.send("hello")
        app.applyLocatorResult(.failure(LocatorError.notFound))
        await turn?.value
        #expect(chat.messages.last?.sender == .error)
    }

    @Test func newClaudePathRebuildsChannel() async {
        let (app, chat, made) = setup()
        app.applyLocatorResult(.success(URL(fileURLWithPath: "/usr/bin/true")))
        await chat.send("one")?.value
        await chat.send("two")?.value
        #expect(made.all.count == 1)
        app.applyLocatorResult(.success(URL(fileURLWithPath: "/bin/echo")))
        await chat.send("three")?.value
        #expect(made.all == [URL(fileURLWithPath: "/usr/bin/true"), URL(fileURLWithPath: "/bin/echo")])
    }
}

// MARK: #10 login-shell lookup can't hang

@Suite struct LoginShellTests {
    private let sh = LoginShell(executable: URL(fileURLWithPath: "/bin/sh"), flags: ["-c"], timeout: .milliseconds(500))

    @Test func returnsOutput() throws {
        #expect(try sh.run("echo /usr/bin/claude") == "/usr/bin/claude\n")
    }

    @Test func hungShellTimesOut() {
        let start = ContinuousClock.now
        #expect(throws: LoginShell.TimedOut.self) { try sh.run("sleep 30") }
        #expect(ContinuousClock.now - start < .seconds(3))
    }

    // A profile that starts a daemon leaves it holding stdout; that mustn't block the result.
    @Test func backgroundChildHoldingStdoutDoesNotBlock() throws {
        let start = ContinuousClock.now
        let out = try LoginShell(executable: URL(fileURLWithPath: "/bin/sh"), flags: ["-c"], timeout: .seconds(10))
            .run("(sleep 5 &); echo /usr/bin/claude")
        #expect(out == "/usr/bin/claude\n")
        #expect(ContinuousClock.now - start < .seconds(3))
    }
}

// MARK: #11 save errors are surfaced, once per failure streak

@MainActor @Suite struct SaveErrorTests {
    @Test func firstFailureNotifiesThenQuietUntilRecovery() throws {
        let root = tempDir("save")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let blocker = root.appendingPathComponent("blocker")
        try Data().write(to: blocker)  // a file where the state folder should be
        let app = AppController(store: StateStore(directory: blocker.appendingPathComponent("state")), sounds: SilentSoundPlayer())
        let shown = Mutex<[String]>([])
        app.onSaveError = { m in shown.withLock { $0.append(m) } }

        app.signOn(screenName: "SkaterBoi99")
        app.setScreenName("SkaterBoi00")
        #expect(shown.withLock { $0.count } == 1)
        #expect(app.saveError != nil)

        try FileManager.default.removeItem(at: blocker)
        app.setScreenName("SkaterBoi01")
        #expect(app.saveError == nil)

        try FileManager.default.removeItem(at: blocker)
        try Data().write(to: blocker)
        app.setScreenName("SkaterBoi02")
        #expect(shown.withLock { $0.count } == 2)
    }
}

// MARK: #14 permission prompts while signed off

@MainActor @Suite struct SignedOffPermissionTests {
    private func setup() -> (AppController, ChatController, Recorded<PermissionDecision>) {
        let app = AppController(store: StateStore(directory: tempDir("off")), sounds: SilentSoundPlayer())
        app.signOn(screenName: "SkaterBoi99")
        let b = app.addBuddy(workingDirectory: URL(fileURLWithPath: "/tmp"))
        let chat = ChatController(buddyID: b.id, app: app) { nil }
        let resolved = Recorded<PermissionDecision>()
        chat.onResolvePermission = { _, d in resolved.add(d) }
        return (app, chat, resolved)
    }

    private func request(_ chat: ChatController) -> PermissionRequest {
        PermissionRequest(id: UUID(), buddyID: chat.buddyID, toolName: "Bash", inputSummary: "Run: ls")
    }

    @Test func requestWhileSignedOffIsDeniedAndNotShown() {
        let (app, chat, resolved) = setup()
        app.signOff()
        #expect(chat.addPermission(request(chat)) == false)
        #expect(!chat.needsAttention)
        #expect(resolved.all == [.deny(ChatController.signedOffDenial)])
        #expect(chat.messages.last?.sender == .system)
    }

    @Test func signOffDeniesOpenPrompts() {
        let (_, chat, resolved) = setup()
        #expect(chat.addPermission(request(chat)))
        chat.denyAllPermissions(ChatController.signedOffDenial)
        #expect(!chat.needsAttention)
        #expect(resolved.all == [.deny(ChatController.signedOffDenial)])
    }
}

// MARK: #15 MCP server ↔ channel wiring, without the real claude

/// Stands in for claude: reads --mcp-config, calls the permission tool over HTTP the way claude does,
/// and replies with the decision's behavior.
private final class PromptingClaude: ProcessLaunching, @unchecked Sendable {
    let toolName = Mutex<String?>(nil)

    func launch(executable: URL, arguments: [String], workingDirectory: URL,
                environment: [String: String], stdin: String) -> any RunningProcess {
        let config = URL(fileURLWithPath: arguments[arguments.firstIndex(of: "--mcp-config")! + 1])
        toolName.withLock { $0 = arguments[arguments.firstIndex(of: "--permission-prompt-tool")! + 1] }
        return ScriptedProcess {
            let json = try JSONSerialization.jsonObject(with: Data(contentsOf: config)) as! [String: Any]
            let servers = json["mcpServers"] as! [String: [String: Any]]
            let url = URL(string: servers["aim"]!["url"] as! String)!
            let list = try await Self.rpc(url, #"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#)
            let tools = (list["tools"] as! [[String: Any]]).map { "mcp__aim__\($0["name"] as! String)" }
            let call = try await Self.rpc(url, #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"approve","arguments":{"tool_name":"Bash","input":{"command":"ls -la"}}}}"#)
            let text = ((call["content"] as! [[String: Any]])[0]["text"] as! String)
            let decision = try JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
            let reply = "\(decision["behavior"]!) via \(tools.joined())"
            return [#"{"type":"result","subtype":"success","is_error":false,"result":"\#(reply)"}"#]
        }
    }

    static func rpc(_ url: URL, _ body: String) async throws -> [String: Any] {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data(body.utf8)
        req.timeoutInterval = 30
        let (data, _) = try await URLSession.shared.data(for: req)
        return (try JSONSerialization.jsonObject(with: data) as! [String: Any])["result"] as! [String: Any]
    }
}

private final class ScriptedProcess: RunningProcess, @unchecked Sendable {
    let lines: AsyncThrowingStream<String, Error>
    private let task: Task<Void, Never>

    init(_ body: @escaping @Sendable () async throws -> [String]) {
        let (s, c) = AsyncThrowingStream<String, Error>.makeStream()
        lines = s
        task = Task {
            do { for l in try await body() { c.yield(l) }; c.finish() } catch { c.finish(throwing: error) }
        }
    }

    func terminate() { task.cancel() }
}

@Suite struct PermissionWiringTests {
    @Test func channelPromptReachesBrokerAndDecisionReachesClaude() async throws {
        let broker = PermissionBroker()
        let server = MCPServer(broker: broker, configDirectory: tempDir("wire"))
        try await server.start()
        defer { server.stop() }
        let b = Buddy(screenName: "xX_Claude_Xx", workingDirectory: URL(fileURLWithPath: "/tmp"))
        let claude = PromptingClaude()
        // Short timeout: the user takes longer than it to answer, and the turn must survive.
        let channel = BuddyChannel(buddy: b, claudePath: URL(fileURLWithPath: "/usr/bin/true"),
                                   mcpConfigPath: try server.configPath(for: b.id), launcher: claude,
                                   inactivityTimeout: .milliseconds(300),
                                   permissionPending: { await broker.pending.contains { $0.buddyID == b.id } })
        let events = Task {
            var out: [ClaudeEvent] = []
            for await e in await channel.send("list files") { out.append(e) }
            return out
        }
        var pending: [PermissionRequest] = []
        for _ in 0..<300 where pending.isEmpty {
            pending = await broker.pending
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(pending.count == 1)
        #expect(pending.first?.buddyID == b.id)
        #expect(pending.first?.inputSummary.contains("ls -la") == true)
        try await Task.sleep(for: .milliseconds(800))
        await broker.resolve(try #require(pending.first).id, .allow)
        #expect(await events.value == [.reply("allow via \(BuddyChannel.permissionToolName)")])
        #expect(claude.toolName.withLock { $0 } == BuddyChannel.permissionToolName)
    }
}
