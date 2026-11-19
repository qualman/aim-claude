import Foundation
import Synchronization
import Testing
@testable import AIMCore

private func request(_ buddy: UUID = UUID(), tool: String = "Bash") -> PermissionRequest {
    PermissionRequest(id: UUID(), buddyID: buddy, toolName: tool, inputSummary: "Running: ls")
}

private func waitForPending(_ broker: PermissionBroker, count: Int = 1) async -> [PermissionRequest] {
    for _ in 0..<200 {
        let p = await broker.pending
        if p.count >= count { return p }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return await broker.pending
}

@Suite struct PermissionBrokerTests {
    @Test func requestWaitsForResolve() async {
        let broker = PermissionBroker()
        let r = request()
        async let decision = broker.request(r)
        _ = await waitForPending(broker)
        await broker.resolve(r.id, .allow)
        #expect(await decision == .allow)
        #expect(await broker.pending.isEmpty)
    }

    @Test func buddiesResolveIndependently() async {
        let broker = PermissionBroker()
        let a = request(), b = request()
        async let da = broker.request(a)
        async let db = broker.request(b)
        _ = await waitForPending(broker, count: 2)
        await broker.resolve(b.id, .deny("no"))
        await broker.resolve(a.id, .allow)
        #expect(await da == .allow)
        #expect(await db == .deny("no"))
    }

    @Test func shutdownDeniesUnresolved() async {
        let broker = PermissionBroker()
        let r = request()
        async let d = broker.request(r)
        _ = await waitForPending(broker)
        await broker.shutdown()
        #expect(await d == .deny("App closed"))
    }

    @Test func notifiesObserver() async {
        let broker = PermissionBroker()
        let seen = Mutex<[UUID]>([])
        await broker.setObserver { r in seen.withLock { $0.append(r.id) } }
        let r = request()
        async let d = broker.request(r)
        _ = await waitForPending(broker)
        #expect(seen.withLock { $0 } == [r.id])
        await broker.resolve(r.id, .allow)
        _ = await d
    }
}

@Suite struct MCPServerTests {
    private func post(_ url: URL, _ body: String) async throws -> (Int, [String: Any]?) {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        req.httpBody = Data(body.utf8)
        req.timeoutInterval = 10
        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as! HTTPURLResponse).statusCode
        return (status, try? JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func start() async throws -> (MCPServer, PermissionBroker, URL, UUID) {
        let broker = PermissionBroker()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("aim-mcp-\(UUID().uuidString)")
        let server = MCPServer(broker: broker, configDirectory: dir)
        try await server.start()
        let buddy = UUID()
        let config = try server.configPath(for: buddy)
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: config)) as! [String: Any]
        let aim = (json["mcpServers"] as! [String: Any])["aim"] as! [String: Any]
        #expect(aim["type"] as? String == "http")
        return (server, broker, URL(string: aim["url"] as! String)!, buddy)
    }

    @Test func configIsLocalhostAndPrivate() async throws {
        let (server, _, url, buddy) = try await start()
        #expect(url.host == "127.0.0.1")
        #expect(url.path.contains(buddy.uuidString.lowercased()))
        let attrs = try FileManager.default.attributesOfItem(atPath: try server.configPath(for: buddy).path)
        #expect((attrs[.posixPermissions] as? Int) == 0o600)
        server.stop()
    }

    @Test func handshakeAndToolList() async throws {
        let (server, _, url, _) = try await start()
        let (s1, init1) = try await post(url, #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}"#)
        #expect(s1 == 200)
        #expect(((init1?["result"] as? [String: Any])?["capabilities"] as? [String: Any])?["tools"] != nil)
        let (s2, _) = try await post(url, #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)
        #expect(s2 == 202)
        let (_, list) = try await post(url, #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#)
        let tools = (list?["result"] as? [String: Any])?["tools"] as? [[String: Any]]
        #expect(tools?.first?["name"] as? String == "approve")
        server.stop()
    }

    @Test func allowEchoesInputAsUpdatedInput() async throws {
        let (server, broker, url, buddy) = try await start()
        async let response = post(url, #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"approve","arguments":{"tool_name":"Bash","input":{"command":"python3 -c \"print(1)\""},"tool_use_id":"t1"}}}"#)
        let pending = await waitForPending(broker)
        #expect(pending.first?.buddyID == buddy)
        #expect(pending.first?.inputSummary == "Run: python3 -c \"print(1)\"")
        await broker.resolve(pending[0].id, .allow)
        let (_, json) = try await response
        let decision = try decisionJSON(json)
        #expect(decision["behavior"] as? String == "allow")
        #expect((decision["updatedInput"] as? [String: Any])?["command"] as? String == "python3 -c \"print(1)\"")
        server.stop()
    }

    @Test func denyCarriesMessage() async throws {
        let (server, broker, url, _) = try await start()
        async let response = post(url, #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"approve","arguments":{"tool_name":"Bash","input":{"command":"rm x"}}}}"#)
        let pending = await waitForPending(broker)
        await broker.resolve(pending[0].id, .deny("The AIM user clicked Deny."))
        let decision = try decisionJSON(try await response.1)
        #expect(decision["behavior"] as? String == "deny")
        #expect(decision["message"] as? String == "The AIM user clicked Deny.")
        server.stop()
    }

    @Test func wrongSecretIsRejected() async throws {
        let (server, broker, url, _) = try await start()
        let bad = URL(string: url.absoluteString.replacingOccurrences(of: url.lastPathComponent, with: "wrong"))!
        let (status, _) = try await post(bad, #"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"approve","arguments":{"tool_name":"Bash","input":{}}}}"#)
        #expect(status == 404)
        #expect(await broker.pending.isEmpty)
        server.stop()
    }

    private func decisionJSON(_ json: [String: Any]?) throws -> [String: Any] {
        let content = ((json?["result"] as? [String: Any])?["content"] as? [[String: Any]])?.first
        let text = try #require(content?["text"] as? String)
        return try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }
}

@MainActor @Suite struct ChatPermissionTests {
    @Test func permissionNeedsAttentionUntilResolved() {
        let store = StateStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("aim-perm-\(UUID().uuidString)"))
        let app = AppController(store: store, sounds: SilentSoundPlayer())
        app.signOn(screenName: "SkaterBoi99")
        let b = app.addBuddy(workingDirectory: URL(fileURLWithPath: "/tmp"))
        let chat = ChatController(buddyID: b.id, app: app) { nil }
        let resolved = Mutex<[(UUID, PermissionDecision)]>([])
        chat.onResolvePermission = { id, d in resolved.withLock { $0.append((id, d)) } }
        let r = PermissionRequest(id: UUID(), buddyID: b.id, toolName: "Bash", inputSummary: "Running: ls")
        chat.addPermission(r)
        #expect(chat.needsAttention)
        #expect(chat.pendingPermissions == [r])
        chat.resolvePermission(r.id, allow: false)
        #expect(!chat.needsAttention)
        #expect(resolved.withLock { $0.first?.1 } == .deny("The AIM user clicked Deny."))
        #expect(chat.messages.last?.sender == .system)
        #expect(chat.messages.last?.text.contains("denied") == true)
    }
}
