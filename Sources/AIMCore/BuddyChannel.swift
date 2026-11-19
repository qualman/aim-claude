import Foundation

public protocol BuddyChanneling: Actor {
    func send(_ text: String) -> AsyncStream<ClaudeEvent>
}

/// One buddy's line to the claude CLI: one process per turn, turns run in order.
public actor BuddyChannel: BuddyChanneling {
    public static let permissionToolName = "mcp__aim__approve"

    private var sessionID: UUID
    private var hasStartedSession: Bool
    private let workingDirectory: URL
    private let claudePath: URL
    private let mcpConfigPath: URL?
    private let launcher: any ProcessLaunching
    private let inactivityTimeout: Duration
    private var tail: Task<Void, Never>?
    private var lastActivity = ContinuousClock.now

    public init(buddy: Buddy, claudePath: URL, mcpConfigPath: URL?, launcher: any ProcessLaunching,
                inactivityTimeout: Duration = .seconds(120)) {
        self.sessionID = buddy.sessionID
        self.hasStartedSession = buddy.hasStartedSession
        self.workingDirectory = buddy.workingDirectory
        self.claudePath = claudePath
        self.mcpConfigPath = mcpConfigPath
        self.launcher = launcher
        self.inactivityTimeout = inactivityTimeout
    }

    public func send(_ text: String) -> AsyncStream<ClaudeEvent> {
        let (stream, cont) = AsyncStream<ClaudeEvent>.makeStream()
        let previous = tail
        tail = Task {
            await previous?.value
            await self.runTurn(text, cont)
            cont.finish()
        }
        return stream
    }

    private func runTurn(_ text: String, _ cont: AsyncStream<ClaudeEvent>.Continuation) async {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: workingDirectory.path, isDirectory: &isDir), isDir.boolValue else {
            cont.yield(.failure("The folder \(workingDirectory.path) no longer exists."))
            return
        }
        var retried = false
        while true {
            let outcome = await attempt(text, cont)
            switch outcome {
            case .done:
                return
            case .sessionLost where !retried:
                retried = true
                sessionID = UUID()
                hasStartedSession = false
                cont.yield(.sessionReset(sessionID))
            case .sessionInUse where !retried:
                retried = true
                hasStartedSession = true
            case .sessionLost, .sessionInUse:
                cont.yield(.failure("Couldn't start a Claude session for this buddy."))
                return
            }
        }
    }

    private enum Outcome { case done, sessionLost, sessionInUse }

    private func attempt(_ text: String, _ cont: AsyncStream<ClaudeEvent>.Continuation) async -> Outcome {
        let process = launcher.launch(executable: claudePath, arguments: arguments(),
                                      workingDirectory: workingDirectory,
                                      environment: ["MCP_TOOL_TIMEOUT": "86400000"],
                                      stdin: Self.stdinLine(text))
        lastActivity = .now
        let timeout = inactivityTimeout
        let watchdog = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: timeout / 4)
                if await self.isStale() { process.terminate(); return true }
            }
            return false
        }
        defer { watchdog.cancel() }

        var parser = EventParser()
        var pending: [ClaudeEvent] = []
        var failure: ProcessFailure?
        do {
            for try await line in process.lines {
                lastActivity = .now
                pending.append(contentsOf: parser.parse(line: line))
                // Hold failures until we know the exit status; activity and replies go out now.
                while let e = pending.first, !Self.isFailure(e) {
                    cont.yield(e)
                    pending.removeFirst()
                    if case .reply = e { hasStartedSession = true }
                }
            }
        } catch let f as ProcessFailure {
            failure = f
        } catch {
            failure = ProcessFailure(status: -1, stderrTail: error.localizedDescription)
        }
        watchdog.cancel()
        if await watchdog.value {
            cont.yield(.failure("Timed out after \(Self.seconds(timeout)) s with no activity."))
            return .done
        }
        if let f = failure {
            if f.stderrTail.contains("No conversation found") { return .sessionLost }
            if f.stderrTail.contains("already in use") { return .sessionInUse }
            let detail = f.stderrTail.isEmpty ? "" : ": \(f.stderrTail)"
            cont.yield(.failure("claude exited with status \(f.status)\(detail)"))
            return .done
        }
        if let e = pending.first {
            cont.yield(e)
        } else if !parser.sawResult {
            cont.yield(.failure("claude ended without replying."))
        }
        return .done
    }

    private func isStale() -> Bool {
        ContinuousClock.now - lastActivity > inactivityTimeout
    }

    private func arguments() -> [String] {
        var a = ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose"]
        a += hasStartedSession ? ["--resume", sessionID.uuidString.lowercased()]
                               : ["--session-id", sessionID.uuidString.lowercased()]
        if let mcp = mcpConfigPath {
            a += ["--mcp-config", mcp.path, "--permission-prompt-tool", Self.permissionToolName]
        }
        return a
    }

    static func stdinLine(_ text: String) -> String {
        let msg: [String: Any] = ["type": "user", "message": ["role": "user", "content": [["type": "text", "text": text]]]]
        let data = try! JSONSerialization.data(withJSONObject: msg, options: [.withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    static func isFailure(_ e: ClaudeEvent) -> Bool {
        if case .failure = e { true } else { false }
    }

    static func seconds(_ d: Duration) -> Int {
        Int(d.components.seconds)
    }
}
