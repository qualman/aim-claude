import Foundation
import Network
import Synchronization

/// A tiny MCP server on 127.0.0.1 exposing one tool, `approve`, which claude calls
/// (via --permission-prompt-tool) before running a tool the user hasn't pre-approved.
/// Each buddy gets its own URL, /buddy/<id>/<secret>, written to a 0600 config file.
public final class MCPServer: Sendable {
    private let broker: PermissionBroker
    private let configDirectory: URL
    private let secret = UUID().uuidString.lowercased()
    private let listener = Mutex<NWListener?>(nil)
    private let port = Mutex<UInt16?>(nil)
    private let queue = DispatchQueue(label: "aim.mcp")

    public init(broker: PermissionBroker, configDirectory: URL) {
        self.broker = broker
        self.configDirectory = configDirectory
    }

    public func start() async throws {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let l = try NWListener(using: params)
        l.newConnectionHandler = { [self] c in
            c.start(queue: queue)
            receive(c, buffer: Data())
        }
        let ready: AsyncStream<Result<UInt16, Error>> = AsyncStream { cont in
            l.stateUpdateHandler = { state in
                switch state {
                case .ready: cont.yield(.success(l.port?.rawValue ?? 0)); cont.finish()
                case .failed(let e): cont.yield(.failure(e)); cont.finish()
                default: break
                }
            }
        }
        l.start(queue: queue)
        listener.withLock { $0 = l }
        for await r in ready { port.withLock { $0 = try? r.get() }; _ = try r.get() }
    }

    public func stop() {
        listener.withLock { $0?.cancel(); $0 = nil }
    }

    /// Writes (or rewrites, since the port changes per launch) this buddy's MCP config.
    public func configPath(for buddyID: UUID) throws -> URL {
        guard let p = port.withLock({ $0 }) else { throw CocoaError(.featureUnsupported) }
        try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let url = "http://127.0.0.1:\(p)/buddy/\(buddyID.uuidString.lowercased())/\(secret)"
        let config: [String: Any] = ["mcpServers": ["aim": ["type": "http", "url": url]]]
        let file = configDirectory.appendingPathComponent("\(buddyID.uuidString.lowercased()).json")
        try JSONSerialization.data(withJSONObject: config).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        return file
    }

    // MARK: HTTP

    private func receive(_ c: NWConnection, buffer: Data) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [self] data, _, done, error in
            var buf = buffer
            if let data { buf.append(data) }
            if let (request, rest) = Self.parse(&buf) {
                Task {
                    let response = await self.handle(request)
                    c.send(content: response, completion: .contentProcessed { _ in })
                    self.receive(c, buffer: rest)
                }
                return
            }
            if done || error != nil { c.cancel(); return }
            receive(c, buffer: buf)
        }
    }

    static let maxBody = 1_000_000

    struct HTTPRequest {
        var method: String
        var path: String
        var body: Data
    }

    /// Returns a complete request and the leftover bytes, or nil if more data is needed.
    static func parse(_ buf: inout Data) -> (HTTPRequest, Data)? {
        guard let headerEnd = buf.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = String(decoding: buf[..<headerEnd.lowerBound], as: UTF8.self)
        let lines = head.components(separatedBy: "\r\n")
        let parts = lines.first?.split(separator: " ") ?? []
        guard parts.count >= 2 else { return nil }
        var length = 0
        for l in lines.dropFirst() {
            let kv = l.split(separator: ":", maxSplits: 1)
            if kv.count == 2, kv[0].lowercased() == "content-length" {
                length = Int(kv[1].trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }
        let bodyStart = headerEnd.upperBound
        // Reject nonsense lengths rather than trapping on a bad range or buffering forever.
        guard (0...maxBody).contains(length) else {
            return (HTTPRequest(method: "BAD", path: "", body: Data()), Data())
        }
        guard buf.count - bodyStart >= length else { return nil }
        let body = buf.subdata(in: bodyStart..<(bodyStart + length))
        let rest = buf.subdata(in: (bodyStart + length)..<buf.count)
        return (HTTPRequest(method: String(parts[0]), path: String(parts[1]), body: body), rest)
    }

    static func response(_ status: Int, _ reason: String, json: Data? = nil) -> Data {
        var head = "HTTP/1.1 \(status) \(reason)\r\nContent-Length: \(json?.count ?? 0)\r\n"
        if json != nil { head += "Content-Type: application/json\r\n" }
        head += "\r\n"
        return Data(head.utf8) + (json ?? Data())
    }

    func handle(_ r: HTTPRequest) async -> Data {
        if r.method == "BAD" { return Self.response(400, "Bad Request") }
        let segments = r.path.split(separator: "/")
        guard segments.count == 3, segments[0] == "buddy", segments[2] == secret,
              let buddyID = UUID(uuidString: String(segments[1])) else {
            return Self.response(404, "Not Found")
        }
        switch r.method {
        case "POST": break
        case "DELETE": return Self.response(200, "OK")
        default: return Self.response(405, "Method Not Allowed")
        }
        guard let msg = try? JSONSerialization.jsonObject(with: r.body) as? [String: Any],
              let method = msg["method"] as? String else {
            return Self.response(400, "Bad Request")
        }
        guard let id = msg["id"] else { return Self.response(202, "Accepted") }
        let result: [String: Any]
        switch method {
        case "initialize":
            let version = (msg["params"] as? [String: Any])?["protocolVersion"] as? String ?? "2025-06-18"
            result = ["protocolVersion": version, "capabilities": ["tools": [:]],
                      "serverInfo": ["name": "aim", "version": "0.1"]]
        case "tools/list":
            result = ["tools": [[
                "name": "approve",
                "description": "Ask the AIM user to approve a tool call.",
                "inputSchema": ["type": "object",
                                "properties": ["tool_name": ["type": "string"], "input": ["type": "object"],
                                               "tool_use_id": ["type": "string"]],
                                "required": ["tool_name", "input"]],
            ]]]
        case "tools/call":
            result = await approve(msg["params"] as? [String: Any] ?? [:], buddyID: buddyID)
        default:
            result = [:]
        }
        let body = try! JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": id, "result": result])
        return Self.response(200, "OK", json: body)
    }

    private func approve(_ params: [String: Any], buddyID: UUID) async -> [String: Any] {
        let args = params["arguments"] as? [String: Any] ?? [:]
        let tool = args["tool_name"] as? String ?? "a tool"
        let input = args["input"] as? [String: Any] ?? [:]
        let request = PermissionRequest(id: UUID(), buddyID: buddyID, toolName: tool,
                                        inputSummary: EventParser.permissionSummary(tool: tool, input: input))
        let decision: [String: Any]
        switch await broker.request(request) {
        case .allow: decision = ["behavior": "allow", "updatedInput": input]
        case .deny(let message): decision = ["behavior": "deny", "message": message]
        }
        let text = String(decoding: try! JSONSerialization.data(withJSONObject: decision), as: UTF8.self)
        return ["content": [["type": "text", "text": text]]]
    }
}
