import Foundation

/// Optional user-supplied art and sounds, looked up by file name. Nothing here ships with the app.
///
///     icons/<name>.png|gif      e.g. send, send-hover, logo
///     sounds/<cue>.wav|mp3|aiff|m4a   buddy-in, buddy-out, received, sent
///     fonts/*.woff2|woff|ttf|otf
public struct SkinStore: Sendable {
    public static let imageTypes = ["png", "gif"]
    public static let soundTypes = ["wav", "mp3", "aiff", "m4a"]
    public static let fontTypes = ["woff2", "woff", "ttf", "otf"]

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// icons/<name>.png or .gif, or nil so the caller draws its fallback. Names are plain words only.
    public func icon(_ name: String) -> URL? {
        find("icons", name, Self.imageTypes)
    }

    /// sounds/<cue name> in any supported format, or nil (no sound).
    public func sound(_ cue: SoundCue) -> URL? {
        find("sounds", cue.fileName, Self.soundTypes)
    }

    /// Font files in fonts/, registered at launch.
    public func fonts() -> [URL] {
        let dir = directory.appendingPathComponent("fonts")
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { Self.fontTypes.contains($0.pathExtension.lowercased()) }
    }

    private func find(_ folder: String, _ name: String, _ types: [String]) -> URL? {
        guard !name.isEmpty, name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else { return nil }
        for t in types {
            let u = directory.appendingPathComponent("\(folder)/\(name).\(t)")
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        return nil
    }
}

public enum SoundCue: String, CaseIterable, Sendable {
    /// Buddies coming online (sign on, add buddy) and going away (sign off).
    case buddyIn, buddyOut
    case received, sent

    /// The file name (without extension) in the skin's sounds folder.
    public var fileName: String {
        switch self {
        case .buddyIn: "buddy-in"
        case .buddyOut: "buddy-out"
        case .received: "received"
        case .sent: "sent"
        }
    }
}

public protocol SoundPlaying: Sendable {
    func play(_ cue: SoundCue)
}

public struct SilentSoundPlayer: SoundPlaying {
    public init() {}
    public func play(_ cue: SoundCue) {}
}

public enum AppPaths {
    /// AIM_SUPPORT_DIR overrides the state location (used for test runs); the skin stays shared.
    public static var support: URL {
        if let dir = ProcessInfo.processInfo.environment["AIM_SUPPORT_DIR"] { return URL(fileURLWithPath: dir) }
        return defaultSupport
    }
    public static var skin: URL { defaultSupport.appendingPathComponent("skin") }
    static var defaultSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AIMClaude")
    }
}
