import Foundation
import Observation

/// Owns app state: screen name, buddies, sign-on, and where `claude` lives. Saves after every change.
@MainActor @Observable
public final class AppController {
    public private(set) var state: AppState
    public private(set) var claudePath: URL?
    public private(set) var claudeMissing = false
    /// Set when the saved state couldn't be read; the bad file is kept beside it.
    public private(set) var loadError: String?
    public private(set) var saveError: String?
    /// True from `beginLocatingClaude()` until the result arrives; sends wait for it.
    public private(set) var isLocatingClaude = false
    /// Called once when saving starts failing, and again only after a save has succeeded since.
    @ObservationIgnored public var onSaveError: ((String) -> Void)?

    @ObservationIgnored private var locatorWaiters: [CheckedContinuation<Void, Never>] = []

    @ObservationIgnored private let store: StateStore
    @ObservationIgnored public let sounds: any SoundPlaying

    public init(store: StateStore, sounds: any SoundPlaying) {
        self.store = store
        self.sounds = sounds
        do {
            state = try store.load()
        } catch {
            state = AppState()
            loadError = "Your saved buddy list couldn't be read, so AIM started fresh. The old file was kept as \(store.quarantine() ?? "state.json")."
        }
        if state.buddies.contains(where: \.pendingTurn) {
            state.markInterruptedTurns()
            save()
        }
    }

    public var showsSignOn: Bool { !state.signedOn || state.screenName == nil }

    @discardableResult
    public func signOn(screenName: String) -> Bool {
        let name = screenName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        state.screenName = name
        state.signedOn = true
        save()
        sounds.play(.buddyIn)
        return true
    }

    public func signOff() {
        state.signedOn = false
        save()
        sounds.play(.buddyOut)
    }

    public func setScreenName(_ name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return }
        state.screenName = n
        save()
    }

    @discardableResult
    public func addBuddy(workingDirectory: URL) -> Buddy {
        let b = Buddy(screenName: BuddyNamer.nextName(existing: state.buddies.map(\.screenName)),
                      workingDirectory: workingDirectory)
        state.buddies.append(b)
        save()
        sounds.play(.buddyIn)
        return b
    }

    public func buddy(_ id: UUID) -> Buddy? {
        state.buddies.first { $0.id == id }
    }

    public func updateBuddy(_ id: UUID, _ mutate: (inout Buddy) -> Void) {
        guard let i = state.buddies.firstIndex(where: { $0.id == id }) else { return }
        mutate(&state.buddies[i])
        save()
    }

    public func setClaudePathOverride(_ path: String?) {
        let trimmed = path?.trimmingCharacters(in: .whitespacesAndNewlines)
        state.claudePathOverride = (trimmed?.isEmpty ?? true) ? nil : trimmed
        save()
    }

    public func beginLocatingClaude() {
        isLocatingClaude = true
    }

    /// Returns once any lookup in progress has finished; immediately if none is.
    public func claudeLocated() async {
        guard isLocatingClaude else { return }
        await withCheckedContinuation { locatorWaiters.append($0) }
    }

    public func applyLocatorResult(_ result: Result<URL, any Error>) {
        defer {
            isLocatingClaude = false
            let waiters = locatorWaiters
            locatorWaiters.removeAll()
            for w in waiters { w.resume() }
        }
        switch result {
        case .success(let url):
            claudePath = url
            claudeMissing = false
        case .failure:
            claudePath = nil
            claudeMissing = true
        }
    }

    private func save() {
        do {
            try store.save(state)
            saveError = nil
        } catch {
            let first = saveError == nil
            saveError = "Couldn't save: \(error.localizedDescription)"
            if first, let message = saveError { onSaveError?(message) }
        }
    }
}
