import AIMCore
import AppKit

/// Plays the skin's sound for a cue, or a short synthesized tone when there isn't one.
final class SoundPlayer: SoundPlaying, @unchecked Sendable {
    private let skin: SkinStore
    private var playing: [NSSound] = []

    init(skin: SkinStore) {
        self.skin = skin
    }

    func play(_ cue: SoundCue) {
        DispatchQueue.main.async { [self] in
            let sound = skin.url(for: cue.asset).flatMap { NSSound(contentsOf: $0, byReference: true) }
                ?? NSSound(data: Fallbacks.tone(for: cue))
            guard let sound else { return }
            playing.removeAll { !$0.isPlaying }
            playing.append(sound)
            sound.play()
        }
    }
}
