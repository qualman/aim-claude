import Foundation
import Synchronization

public struct ProcessFailure: Error, Equatable, Sendable {
    public var status: Int32
    public var stderrTail: String

    public init(status: Int32, stderrTail: String) {
        self.status = status
        self.stderrTail = stderrTail
    }
}

public protocol RunningProcess: Sendable {
    /// stdout lines; finishes on exit 0, throws `ProcessFailure` otherwise.
    var lines: AsyncThrowingStream<String, Error> { get }
    func terminate()
}

public protocol ProcessLaunching: Sendable {
    func launch(executable: URL, arguments: [String], workingDirectory: URL,
                environment: [String: String], stdin: String) -> any RunningProcess
}

/// Launches real processes. `basePATH` should come from the login shell, since
/// apps opened from Finder don't inherit the terminal's PATH.
public struct SystemProcessLauncher: ProcessLaunching {
    let basePATH: String?

    public init(basePATH: String?) {
        self.basePATH = basePATH
    }

    public func launch(executable: URL, arguments: [String], workingDirectory: URL,
                       environment: [String: String], stdin: String) -> any RunningProcess {
        var env = ProcessInfo.processInfo.environment
        if let basePATH { env["PATH"] = basePATH }
        env.merge(environment) { _, new in new }
        return SystemProcess(executable: executable, arguments: arguments, cwd: workingDirectory, env: env, stdin: stdin)
    }
}

final class SystemProcess: RunningProcess, @unchecked Sendable {
    let lines: AsyncThrowingStream<String, Error>
    private let process = Process()
    private static let stderrLimit = 2000

    init(executable: URL, arguments: [String], cwd: URL, env: [String: String], stdin: String) {
        let process = self.process
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = cwd
        process.environment = env
        let out = Pipe(), err = Pipe(), input = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = input

        let stderrBuf = Mutex(Data())
        err.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            stderrBuf.withLock { buf in
                buf.append(d)
                if buf.count > Self.stderrLimit * 2 { buf = buf.suffix(Self.stderrLimit) }
            }
        }
        let exited = AsyncStream<Int32>.makeStream()
        process.terminationHandler = { p in
            exited.continuation.yield(p.terminationStatus)
            exited.continuation.finish()
        }

        lines = AsyncThrowingStream { cont in
            do {
                try process.run()
            } catch {
                cont.finish(throwing: ProcessFailure(status: -1, stderrTail: "Couldn't start claude: \(error.localizedDescription)"))
                return
            }
            input.fileHandleForWriting.write(Data(stdin.utf8))
            try? input.fileHandleForWriting.close()
            Task {
                do {
                    for try await line in out.fileHandleForReading.bytes.lines { cont.yield(line) }
                } catch {}
                var status: Int32 = 0
                for await s in exited.stream { status = s }
                err.fileHandleForReading.readabilityHandler = nil
                let tail = stderrBuf.withLock { String(decoding: $0.suffix(Self.stderrLimit), as: UTF8.self) }
                if status == 0 {
                    cont.finish()
                } else {
                    cont.finish(throwing: ProcessFailure(status: status, stderrTail: tail.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
            }
        }
    }

    func terminate() {
        if process.isRunning { process.terminate() }
    }
}
