import Foundation
import Testing
@testable import AIMCore

@Suite struct SkinStoreTests {
    private func dir() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("aim-skin-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    @Test func returnsPresentFile() throws {
        let d = try dir()
        try Data([1]).write(to: d.appendingPathComponent("received.mp3"))
        #expect(SkinStore(directory: d).url(for: .received)?.lastPathComponent == "received.mp3")
        #expect(SkinStore(directory: d).url(for: .doorOpen) == nil)
    }

    @Test func emptyDirectoryHasNothing() throws {
        let s = SkinStore(directory: try dir())
        for a in SkinAsset.allCases { #expect(s.url(for: a) == nil) }
    }

    @Test func missingDirectoryHasNothing() {
        let s = SkinStore(directory: URL(fileURLWithPath: "/tmp/aim-nope-\(UUID().uuidString)"))
        #expect(s.url(for: .logo) == nil)
    }

    @Test func cueMapsToSkinFile() {
        #expect(SoundCue.buddyIn.asset == .doorOpen)
        #expect(SoundCue.buddyOut.asset == .doorClose)
        #expect(SoundCue.received.asset == .received)
        #expect(SoundCue.sent.asset == .sent)
        #expect(SkinAsset.received.rawValue == "received.mp3")
        #expect(SkinAsset.sent.rawValue == "sent.mp3")
    }
}

@Suite struct SkinIconTests {
    private func dir() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("aim-skin-icons-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d.appendingPathComponent("icons"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: d.appendingPathComponent("fonts"), withIntermediateDirectories: true)
        return d
    }

    @Test func iconFoundByName() throws {
        let d = try dir()
        try Data([1]).write(to: d.appendingPathComponent("icons/send.png"))
        let s = SkinStore(directory: d)
        #expect(s.icon("send")?.lastPathComponent == "send.png")
        #expect(s.icon("warn") == nil)
    }

    @Test func iconNameCannotEscapeSkinFolder() throws {
        let s = SkinStore(directory: try dir())
        #expect(s.icon("../../etc/passwd") == nil)
    }

    @Test func fontsListsOnlyFontFiles() throws {
        let d = try dir()
        for f in ["a.woff2", "b.ttf", "c.otf", "notes.txt"] { try Data([1]).write(to: d.appendingPathComponent("fonts/\(f)")) }
        #expect(SkinStore(directory: d).fonts().map(\.lastPathComponent).sorted() == ["a.woff2", "b.ttf", "c.otf"])
    }
}
