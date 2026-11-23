import Foundation
import Testing
@testable import AIMCore

@MainActor private func app(_ sounds: any SoundPlaying = SilentSoundPlayer()) -> (AppController, StateStore) {
    let s = StateStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("aim-away-\(UUID().uuidString)"))
    let a = AppController(store: s, sounds: sounds)
    a.signOn(screenName: "SkaterBoi99")
    return (a, s)
}

private let t0 = Date(timeIntervalSince1970: 1_000_000)

@MainActor @Suite struct AwayTests {
    @Test func repliesAreCountedPerBuddyOnlyWhileAway() {
        let (a, _) = app()
        let x = a.addBuddy(workingDirectory: URL(fileURLWithPath: "/tmp"))
        let y = a.addBuddy(workingDirectory: URL(fileURLWithPath: "/tmp"))
        a.noteBuddyMessage(x.id, at: t0)  // not away yet
        a.goAway(AwayMessage(label: "brb", text: "eating dinner"), save: false, at: t0)
        a.noteBuddyMessage(x.id, at: t0 + 10)
        a.noteBuddyMessage(y.id, at: t0 + 20)
        a.noteBuddyMessage(x.id, at: t0 + 30)
        let away = try! #require(a.away)
        #expect(away.messageCount == 3)
        #expect(away.peopleCount == 2)
        #expect(away.tallies[x.id]?.count == 2)
        #expect(away.tallies[x.id]?.lastSent == t0 + 30)
        a.goAway(AwayMessage(label: "zzz", text: "asleep"), save: false, at: t0 + 40)
        #expect(a.away?.message.text == "asleep")
        #expect(a.away?.messageCount == 3)  // switching messages keeps the count
        a.comeBack()
        #expect(a.away == nil)
    }

    @Test func chatReplyIsCountedButNothingIsSentToClaude() async {
        let (a, _) = app()
        let b = a.addBuddy(workingDirectory: URL(fileURLWithPath: "/tmp"))
        let fake = FakeChannel([[.reply("done")]])
        let chat = ChatController(buddyID: b.id, app: a) { fake }
        a.goAway(AwayMessage(label: "brb", text: "eating dinner"), save: false)
        await chat.send("run the tests")?.value
        #expect(a.away?.messageCount == 1)
        #expect(await fake.sent == ["run the tests"])  // the away message itself never goes to claude
    }

    @Test func sortsByNameThenCountThenLastSent() {
        var s = AwayStatus(message: AwayMessage(label: "x", text: "x"), since: t0)
        let a = UUID(), b = UUID(), c = UUID()
        s.record(buddyID: b, screenName: "Claude2", at: t0 + 1)
        s.record(buddyID: a, screenName: "alpha", at: t0 + 2)
        s.record(buddyID: a, screenName: "alpha", at: t0 + 3)
        s.record(buddyID: c, screenName: "Claude10", at: t0 + 9)
        // Case-insensitive, and numbers compare as numbers (2 before 10).
        #expect(s.rows(sortedBy: .name).map(\.screenName) == ["alpha", "Claude2", "Claude10"])
        #expect(s.rows(sortedBy: .count).map(\.buddyID) == [a, b, c])  // b and c tie on count; name breaks it
        #expect(s.rows(sortedBy: .lastSent).map(\.buddyID) == [c, a, b])
    }

    @Test func savingReplacesSameLabelAndPersists() throws {
        let (a, store) = app()
        a.goAway(AwayMessage(label: "brb", text: "eating dinner"), save: true)
        a.goAway(AwayMessage(label: " brb ", text: "eating dessert"), save: true)
        a.goAway(AwayMessage(label: "zzz", text: "asleep"), save: false)
        #expect(a.state.savedAwayMessages.map(\.text) == ["eating dessert"])
        #expect(try store.load().savedAwayMessages.map(\.label) == ["brb"])
        a.deleteSavedAwayMessage(a.state.savedAwayMessages[0].id)
        #expect(try store.load().savedAwayMessages.isEmpty)
    }

    @Test func blankLabelTakesTheMessagesFirstLine() {
        let (a, _) = app()
        a.goAway(AwayMessage(label: "  ", text: "at the gym\nback at 6"), save: true)
        #expect(a.state.savedAwayMessages.first?.label == "at the gym")
    }

    @Test func muteSilencesEveryCueUntilBack() async {
        let sounds = RecordingSounds()
        let (a, _) = app(sounds)
        let b = a.addBuddy(workingDirectory: URL(fileURLWithPath: "/tmp"))
        let before = sounds.cues.withLock { $0.count }
        a.goAway(AwayMessage(label: "brb", text: "x"), save: false)
        a.setAwayOptions(muteSounds: true)
        let chat = ChatController(buddyID: b.id, app: a) { FakeChannel([[.reply("hi")]]) }
        await chat.send("hello")?.value
        #expect(sounds.cues.withLock { $0.count } == before)
        a.comeBack()
        await chat.send("again")?.value
        #expect(sounds.cues.withLock { $0.count } > before)
    }

    @Test func signOffEndsAway() {
        let (a, _) = app()
        a.goAway(AwayMessage(label: "brb", text: "x"), save: false)
        a.signOff()
        #expect(a.away == nil)
    }

    @Test func expandsDateAndTime() {
        let s = AwayStatus.expand("gone since %t on %d", at: t0)
        #expect(!s.contains("%t") && !s.contains("%d"))
        #expect(s.contains(t0.formatted(date: .omitted, time: .shortened)))
    }

    @Test func stateFromBeforeAwayMessagesStillLoads() throws {
        let old = #"{"buddies":[],"signedOn":false,"screenName":"SkaterBoi99"}"#
        let s = try JSONDecoder().decode(AppState.self, from: Data(old.utf8))
        #expect(s.savedAwayMessages.isEmpty)
        #expect(s.screenName == "SkaterBoi99")
    }
}
