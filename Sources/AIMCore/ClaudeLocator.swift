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
public struct LoginShell: ShellRunning {
    public init() {}

    public func run(_ command: String) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lic", command]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
