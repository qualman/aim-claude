import Foundation

public protocol ShellRunning: Sendable {
    func run(_ command: String) throws -> String
}

public enum LocatorError: Error, Equatable {
    case notFound
}

public enum ClaudeLocator {
    /// An executable override wins; otherwise the last absolute path the login shell prints
    /// (profiles can print noise before it).
    public static func locate(override: String?, shell: any ShellRunning) throws -> URL {
        let fm = FileManager.default
        if let o = override, fm.isExecutableFile(atPath: o) { return URL(fileURLWithPath: o) }
        let output = (try? shell.run("command -v claude")) ?? ""
        let candidate = output.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { $0.hasPrefix("/") }
        guard let path = candidate, fm.isExecutableFile(atPath: path) else { throw LocatorError.notFound }
        return URL(fileURLWithPath: path)
    }
}

/// Runs commands in the user's login + interactive zsh, so PATH matches their terminal.
/// Output goes to a temp file rather than a pipe: a profile that starts a daemon leaves it holding
/// stdout, and a pipe would then never reach end-of-file. A shell that doesn't exit is killed.
public struct LoginShell: ShellRunning {
    public struct TimedOut: Error {}

    let executable: URL
    let flags: [String]
    let timeout: Duration

    public init(executable: URL = URL(fileURLWithPath: "/bin/zsh"), flags: [String] = ["-lic"],
                timeout: Duration = .seconds(15)) {
        self.executable = executable
        self.flags = flags
        self.timeout = timeout
    }

    public func run(_ command: String) throws -> String {
        let fm = FileManager.default
        let outFile = fm.temporaryDirectory.appendingPathComponent("aim-shell-\(UUID().uuidString)")
        guard fm.createFile(atPath: outFile.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        defer { try? fm.removeItem(at: outFile) }
        let out = try FileHandle(forWritingTo: outFile)
        defer { try? out.close() }

        let p = Process()
        p.executableURL = executable
        p.arguments = flags + [command]
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in exited.signal() }
        try p.run()
        let c = timeout.components
        let seconds = Double(c.seconds) + Double(c.attoseconds) / 1e18
        if exited.wait(timeout: .now() + seconds) == .timedOut {
            p.terminate()
            throw TimedOut()
        }
        return String(decoding: (try? Data(contentsOf: outFile)) ?? Data(), as: UTF8.self)
    }
}
