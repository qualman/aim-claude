import Foundation
import Synchronization
import Testing
@testable import AIMCore

/// A scripted process: yields `lines`, then exits with `status`/`stderr`.
/// With `hang: true` it yields nothing until terminated.
final class FakeProcess: RunningProcess, @unchecked Sendable {
    let lines: AsyncThrowingStream<String, Error>
    private let cont: AsyncThrowingStream<String, Error>.Continuation
    let terminated = Mutex(false)

    init(lines: [String], status: Int32 = 0, stderr: String = "", hang: Bool = false, delay: Duration = .zero) {
        let (s, c) = AsyncThrowingStream<String, Error>.makeStream()
        self.lines = s
        self.cont = c
        guard !hang else { return }
        Task {
            if delay != .zero { try? await Task.sleep(for: delay) }
            for l in lines { c.yield(l) }
            if status == 0 { c.finish() } else { c.finish(throwing: ProcessFailure(status: status, stderrTail: stderr)) }
        }
    }

    func terminate() {
        terminated.withLock { $0 = true }
        cont.finish(throwing: ProcessFailure(status: 15, stderrTail: ""))
    }
}

struct Launch: Sendable {
    let arguments: [String]
    let workingDirectory: URL
    let environment: [String: String]
    let stdin: String
}

final class FakeLauncher: ProcessLaunching, @unchecked Sendable {
    let launches = Mutex<[Launch]>([])
    let active = Mutex(0)
    let maxActive = Mutex(0)
    private let script: Mutex<[FakeProcess]>

    init(_ script: [FakeProcess]) { self.script = Mutex(script) }

    func launch(executable: URL, arguments: [String], workingDirectory: URL,
                environment: [String: String], stdin: String) -> any RunningProcess {
        launches.withLock { $0.append(Launch(arguments: arguments, workingDirectory: workingDirectory, environment: environment, stdin: stdin)) }
        let n = active.withLock { $0 += 1; return $0 }
        maxActive.withLock { $0 = max($0, n) }
        let p = script.withLock { $0.removeFirst() }
        return Tracked(p) { [self] in active.withLock { $0 -= 1 } }
    }
}

/// Decrements the launcher's active count when the wrapped stream ends.
final class Tracked: RunningProcess, @unchecked Sendable {
    let inner: FakeProcess
    let lines: AsyncThrowingStream<String, Error>
    init(_ inner: FakeProcess, onEnd: @escaping @Sendable () -> Void) {
        self.inner = inner
        let src = inner.lines
        lines = AsyncThrowingStream { c in
            Task {
                do { for try await l in src { c.yield(l) }; c.finish() } catch { c.finish(throwing: error) }
                onEnd()
            }
        }
    }
    func terminate() { inner.terminate() }
}

private let result = #"{"type":"result","subtype":"success","is_error":false,"result":"hi there"}"#
private let toolUse = #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"ls"}}]}}"#

private func buddy(dir: URL = URL(fileURLWithPath: "/tmp"), started: Bool = false) -> Buddy {
    Buddy(screenName: "xX_Claude_Xx", workingDirectory: dir, hasStartedSession: started)
}

private func collect(_ s: AsyncStream<ClaudeEvent>) async -> [ClaudeEvent] {
    var out: [ClaudeEvent] = []
    for await e in s { out.append(e) }
    return out
}

private func channel(_ b: Buddy, _ l: FakeLauncher, mcp: URL? = nil, timeout: Duration = .seconds(120)) -> BuddyChannel {
    BuddyChannel(buddy: b, claudePath: URL(fileURLWithPath: "/usr/bin/true"), mcpConfigPath: mcp, launcher: l, inactivityTimeout: timeout)
}

@Suite struct BuddyChannelTests {
    @Test func firstSendUsesSessionIDThenResume() async {
        let b = buddy()
        let l = FakeLauncher([FakeProcess(lines: [result]), FakeProcess(lines: [result])])
        let c = channel(b, l)
        _ = await collect(await c.send("one"))
        _ = await collect(await c.send("two"))
        let args = l.launches.withLock { $0.map(\.arguments) }
        #expect(args[0].contains("--session-id"))
        #expect(args[0].contains(b.sessionID.uuidString.lowercased()))
        #expect(args[1].contains("--resume"))
        #expect(!args[1].contains("--session-id"))
    }

    @Test func passesStreamJSONFlagsAndWorkingDirectory() async {
        let dir = FileManager.default.temporaryDirectory
        let l = FakeLauncher([FakeProcess(lines: [result])])
        let c = channel(buddy(dir: dir), l, mcp: URL(fileURLWithPath: "/tmp/mcp.json"))
        _ = await collect(await c.send("hello"))
        let launch = l.launches.withLock { $0[0] }
        for flag in ["-p", "--input-format", "stream-json", "--output-format", "--verbose",
                     "--mcp-config", "/tmp/mcp.json", "--permission-prompt-tool", "mcp__aim__approve"] {
            #expect(launch.arguments.contains(flag), "missing \(flag)")
        }
        #expect(launch.workingDirectory == dir)
        #expect(launch.environment["MCP_TOOL_TIMEOUT"] != nil)
        #expect(launch.stdin.contains(#""text":"hello""#))
        #expect(launch.stdin.hasSuffix("\n"))
    }

    @Test func emitsActivityThenReply() async {
        let l = FakeLauncher([FakeProcess(lines: [toolUse, "garbage", result])])
        let e = await collect(await channel(buddy(), l).send("x"))
        #expect(e == [.activity("Running: ls"), .reply("hi there")])
    }

    @Test func queuedSendsRunSequentially() async {
        let l = FakeLauncher([FakeProcess(lines: [result], delay: .milliseconds(100)), FakeProcess(lines: [result])])
        let c = channel(buddy(), l)
        let s1 = await c.send("one")
        let s2 = await c.send("two")
        async let a = collect(s1)
        async let b = collect(s2)
        _ = await (a, b)
        #expect(l.maxActive.withLock { $0 } == 1)
        #expect(l.launches.withLock { $0.map(\.stdin) }.first?.contains("one") == true)
    }

    @Test func nonZeroExitIsFailureWithStderrTail() async {
        let l = FakeLauncher([FakeProcess(lines: [], status: 2, stderr: "boom: bad thing")])
        let e = await collect(await channel(buddy(), l).send("x"))
        #expect(e.count == 1)
        guard case .failure(let msg) = e.first else { Issue.record("\(e)"); return }
        #expect(msg.contains("boom: bad thing"))
    }

    @Test func inactivityTimesOutAndTerminates() async {
        let p = FakeProcess(lines: [], hang: true)
        let l = FakeLauncher([p])
        let e = await collect(await channel(buddy(), l, timeout: .milliseconds(200)).send("x"))
        #expect(p.terminated.withLock { $0 })
        guard case .failure(let msg) = e.last else { Issue.record("\(e)"); return }
        #expect(msg.hasPrefix("Timed out"))
    }

    @Test func missingWorkingDirectoryFailsWithoutLaunching() async {
        let gone = URL(fileURLWithPath: "/tmp/aim-gone-\(UUID().uuidString)")
        let l = FakeLauncher([])
        let e = await collect(await channel(buddy(dir: gone), l).send("x"))
        #expect(l.launches.withLock { $0.isEmpty })
        guard case .failure(let msg) = e.first else { Issue.record("\(e)"); return }
        #expect(msg.contains(gone.path))
    }

    @Test func lostSessionResetsAndRetriesOnce() async {
        let bad = #"{"type":"result","subtype":"error_during_execution","is_error":true,"result":""}"#
        let l = FakeLauncher([
            FakeProcess(lines: [bad], status: 1, stderr: "No conversation found with session ID: abc"),
            FakeProcess(lines: [result]),
        ])
        let b = buddy(started: true)
        let e = await collect(await channel(b, l).send("x"))
        guard case .sessionReset(let newID) = e.first else { Issue.record("\(e)"); return }
        #expect(newID != b.sessionID)
        #expect(e.last == .reply("hi there"))
        let args = l.launches.withLock { $0.map(\.arguments) }
        #expect(args[1].contains("--session-id"))
        #expect(args[1].contains(newID.uuidString.lowercased()))
    }

    @Test func sessionAlreadyInUseRetriesWithResume() async {
        let l = FakeLauncher([
            FakeProcess(lines: [], status: 1, stderr: "Error: Session ID abc is already in use."),
            FakeProcess(lines: [result]),
        ])
        let e = await collect(await channel(buddy(started: false), l).send("x"))
        #expect(e == [.reply("hi there")])
        #expect(l.launches.withLock { $0[1].arguments }.contains("--resume"))
    }
}

struct FakeShell: ShellRunning {
    let output: String
    func run(_ command: String) throws -> String { output }
}

@Suite struct ClaudeLocatorTests {
    @Test func notFoundWhenShellPrintsNothing() {
        #expect(throws: LocatorError.notFound) { try ClaudeLocator.locate(override: nil, shell: FakeShell(output: "")) }
    }
    @Test func prefersExecutableOverride() throws {
        let u = try ClaudeLocator.locate(override: "/bin/ls", shell: FakeShell(output: "/bin/cat\n"))
        #expect(u.path == "/bin/ls")
    }
    @Test func ignoresNonExecutableOverride() throws {
        let u = try ClaudeLocator.locate(override: "/nope/claude", shell: FakeShell(output: "/bin/cat\n"))
        #expect(u.path == "/bin/cat")
    }
    @Test func takesLastAbsolutePathFromNoisyShell() throws {
        let u = try ClaudeLocator.locate(override: nil, shell: FakeShell(output: "Welcome!\nnvm loaded\n/bin/cat\n"))
        #expect(u.path == "/bin/cat")
    }
}
