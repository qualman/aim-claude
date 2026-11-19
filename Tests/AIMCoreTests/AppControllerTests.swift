import Foundation
import Synchronization
import Testing
@testable import AIMCore

final class RecordingSounds: SoundPlaying, @unchecked Sendable {
    let cues = Mutex<[SoundCue]>([])
    func play(_ cue: SoundCue) { cues.withLock { $0.append(cue) } }
}

private func tempStore() -> StateStore {
    StateStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("aim-app-\(UUID().uuidString)"))
}

@MainActor @Suite struct AppControllerTests {
    @Test func signOnSetsNameAndPlaysWelcome() {
        let sounds = RecordingSounds()
        let c = AppController(store: tempStore(), sounds: sounds)
        #expect(c.showsSignOn)
        #expect(c.signOn(screenName: "  SkaterBoi99 "))
        #expect(c.state.screenName == "SkaterBoi99")
        #expect(c.state.signedOn)
        #expect(!c.showsSignOn)
        #expect(sounds.cues.withLock { $0 } == [.welcome])
    }

    @Test func rejectsBlankScreenName() {
        let c = AppController(store: tempStore(), sounds: SilentSoundPlayer())
        #expect(!c.signOn(screenName: "   "))
        #expect(!c.state.signedOn)
    }

    @Test func signOffKeepsBuddies() {
        let sounds = RecordingSounds()
        let c = AppController(store: tempStore(), sounds: sounds)
        c.signOn(screenName: "me")
        c.addBuddy(workingDirectory: URL(fileURLWithPath: "/tmp"))
        c.signOff()
        #expect(!c.state.signedOn)
        #expect(c.state.buddies.count == 1)
        #expect(sounds.cues.withLock { $0 }.last == .goodbye)
    }

    @Test func addBuddyNamesPersistsAndPlaysDoor() throws {
        let store = tempStore()
        let sounds = RecordingSounds()
        let c = AppController(store: store, sounds: sounds)
        c.signOn(screenName: "me")
        let a = c.addBuddy(workingDirectory: URL(fileURLWithPath: "/tmp"))
        let b = c.addBuddy(workingDirectory: URL(fileURLWithPath: "/var"))
        #expect(a.screenName == "xX_Claude_Xx")
        #expect(b.screenName == "xX_Claude2_Xx")
        #expect(a.sessionID != b.sessionID)
        #expect(!a.hasStartedSession)
        #expect(try store.load().buddies.map(\.screenName) == ["xX_Claude_Xx", "xX_Claude2_Xx"])
        #expect(sounds.cues.withLock { $0 }.last == .buddyIn)
    }

    @Test func relaunchWhileSignedOnSkipsSignOn() throws {
        let store = tempStore()
        AppController(store: store, sounds: SilentSoundPlayer()).signOn(screenName: "me")
        let again = AppController(store: store, sounds: SilentSoundPlayer())
        #expect(!again.showsSignOn)
        #expect(again.state.screenName == "me")
    }

    @Test func launchMarksInterruptedTurns() throws {
        let store = tempStore()
        var s = AppState(screenName: "me", signedOn: true)
        s.buddies = [Buddy(screenName: "xX_Claude_Xx", workingDirectory: URL(fileURLWithPath: "/tmp"), pendingTurn: true)]
        try store.save(s)
        let c = AppController(store: store, sounds: SilentSoundPlayer())
        #expect(c.state.buddies[0].pendingTurn == false)
        #expect(c.state.buddies[0].messages.last?.text == "Interrupted when the app quit.")
        #expect(try store.load().buddies[0].pendingTurn == false)
    }

    @Test func corruptStateIsSetAsideNotOverwritten() throws {
        let store = tempStore()
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try Data("{oops".utf8).write(to: store.directory.appendingPathComponent("state.json"))
        let c = AppController(store: store, sounds: SilentSoundPlayer())
        #expect(c.loadError != nil)
        #expect(c.showsSignOn)
        let files = try FileManager.default.contentsOfDirectory(atPath: store.directory.path)
        #expect(files.contains { $0.hasPrefix("state.json.corrupt") })
    }

    @Test func updateBuddyMutatesAndPersists() throws {
        let store = tempStore()
        let c = AppController(store: store, sounds: SilentSoundPlayer())
        let b = c.addBuddy(workingDirectory: URL(fileURLWithPath: "/tmp"))
        c.updateBuddy(b.id) { $0.hasStartedSession = true }
        #expect(c.buddy(b.id)?.hasStartedSession == true)
        #expect(try store.load().buddies[0].hasStartedSession)
    }

    @Test func missingClaudeIsReported() {
        let c = AppController(store: tempStore(), sounds: SilentSoundPlayer())
        c.applyLocatorResult(.failure(LocatorError.notFound))
        #expect(c.claudePath == nil)
        #expect(c.claudeMissing)
    }

    @Test func setScreenNameRenames() {
        let c = AppController(store: tempStore(), sounds: SilentSoundPlayer())
        c.signOn(screenName: "old")
        c.setScreenName("new")
        #expect(c.state.screenName == "new")
    }
}

@MainActor @Suite struct ClaudePathOverrideTests {
    @Test func overrideIsSavedAndBlankClears() throws {
        let store = StateStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("aim-ovr-\(UUID().uuidString)"))
        let c = AppController(store: store, sounds: SilentSoundPlayer())
        c.setClaudePathOverride("  /opt/claude  ")
        #expect(try store.load().claudePathOverride == "/opt/claude")
        c.setClaudePathOverride("   ")
        #expect(c.state.claudePathOverride == nil)
    }
}
