import Foundation

public protocol BuddyChanneling: Actor {
    func send(_ text: String) -> AsyncStream<ClaudeEvent>
    /// Stops the running turn's process and drops queued turns. Later sends do nothing.
    func close()
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
    private var running: (any RunningProcess)?
    private var closed = false

    /// Longer than claude's 10-minute maximum tool runtime: stream-json is silent while a tool runs.
    public static let defaultInactivityTimeout: Duration = .seconds(660)

    private let permissionPending: (@Sendable () async -> Bool)?

    /// `permissionPending` reports whether this buddy is waiting on the user's Allow/Deny;
    /// the inactivity timeout doesn't count that time.
    public init(buddy: Buddy, claudePath: URL, mcpConfigPath: URL?, launcher: any ProcessLaunching,
                inactivityTimeout: Duration = BuddyChannel.defaultInactivityTimeout,
                permissionPending: (@Sendable () async -> Bool)? = nil) {
        self.permissionPending = permissionPending
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

    public func close() {
        closed = true
        running?.terminate()
        running = nil
    }

    private func runTurn(_ text: String, _ cont: AsyncStream<ClaudeEvent>.Continuation) async {
        guard !closed else { return }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: workingDirectory.path, isDirectory: &isDir), isDir.boolValue else {
            cont.yield(.failure("The folder \(workingDirectory.path) no longer exists."))
            return
        }
        var retried = false
        while !closed {
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
        running = process
        defer { running = nil }
        lastActivity = .now
        let timeout = inactivityTimeout
        let watchdog = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: timeout / 4)
                if self.isStale() {
                    if await self.permissionPending?() == true {
                        self.markActive()
                    } else {
                        process.terminate()
                        return true
                    }
                }
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
        // Closed (the buddy was removed): the process was killed on purpose, so report nothing.
        if closed { return .done }
        if let f = failure {
            // claude reports some errors on stderr and some in result.errors; check both.
            let reported = pending.compactMap { if case .failure(let m) = $0 { m } else { nil } }.joined(separator: "; ")
            let evidence = f.stderrTail + "\n" + reported
            if evidence.contains("No conversation found") { return .sessionLost }
            if evidence.contains("already in use") { return .sessionInUse }
            let detail = [reported, f.stderrTail].filter { !$0.isEmpty }.joined(separator: " — ")
            cont.yield(.failure("claude exited with status \(f.status)\(detail.isEmpty ? "" : ": \(detail)")"))
            return .done
        }
        if let e = pending.first {
            cont.yield(e)
        } else if !parser.sawResult {
            cont.yield(.failure("claude ended without replying."))
        }
        return .done
    }

    private func markActive() {
        lastActivity = .now
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
