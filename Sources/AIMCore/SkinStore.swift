import Foundation

/// Optional user-supplied art and sounds. Nothing here ships with the app.
public enum SkinAsset: String, CaseIterable, Sendable {
    case logo = "logo.png"
    case doorOpen = "door-open.wav"
    case doorClose = "door-close.wav"
    case im = "im.wav"
    case welcome = "welcome.wav"
    case goodbye = "goodbye.wav"
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
}

public enum SoundCue: Sendable {
    case buddyIn, buddyOut, message, welcome, goodbye

    public var asset: SkinAsset {
        switch self {
        case .buddyIn: .doorOpen
        case .buddyOut: .doorClose
        case .message: .im
        case .welcome: .welcome
        case .goodbye: .goodbye
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
    public static var support: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AIMClaude")
    }
    public static var skin: URL { support.appendingPathComponent("skin") }
}
