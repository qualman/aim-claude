import Foundation

/// Optional user-supplied art and sounds. Nothing here ships with the app.
public enum SkinAsset: String, CaseIterable, Sendable {
    case logo = "logo.png"
    case doorOpen = "door-open.wav"
    case doorClose = "door-close.wav"
    case received = "received.mp3"
    case sent = "sent.mp3"
}

public struct SkinStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// nil when the file isn't there, so callers use the built-in fallback.
    public func url(for asset: SkinAsset) -> URL? {
        let u = directory.appendingPathComponent(asset.rawValue)
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }

    /// icons/<name>.png, or nil so the caller draws its fallback. Names are plain words only.
    public func icon(_ name: String) -> URL? {
        guard !name.isEmpty, name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else { return nil }
        let u = directory.appendingPathComponent("icons/\(name).png")
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }

    /// Font files in fonts/, registered at launch.
    public func fonts() -> [URL] {
        let dir = directory.appendingPathComponent("fonts")
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { ["woff2", "woff", "ttf", "otf"].contains($0.pathExtension.lowercased()) }
    }
}

public enum SoundCue: Sendable {
    /// Buddies coming online (sign on, add buddy) and going away (sign off).
    case buddyIn, buddyOut
    case received, sent

    public var asset: SkinAsset {
        switch self {
        case .buddyIn: .doorOpen
        case .buddyOut: .doorClose
        case .received: .received
        case .sent: .sent
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
