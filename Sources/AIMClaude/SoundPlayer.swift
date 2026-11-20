import AIMCore
import AppKit

/// Plays the skin's sound for a cue. No skin file, no sound.
final class SoundPlayer: SoundPlaying, @unchecked Sendable {
    private let skin: SkinStore
    private var playing: [NSSound] = []

    init(skin: SkinStore) {
        self.skin = skin
    }

    func play(_ cue: SoundCue) {
        DispatchQueue.main.async { [self] in
            // Only the user's own sound files play; a missing or unreadable file is silent.
            guard let sound = skin.sound(cue).flatMap({ NSSound(contentsOf: $0, byReference: true) }) else { return }
            playing.removeAll { !$0.isPlaying }
            playing.append(sound)
            sound.play()
        }
    }
}
