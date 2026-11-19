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
        try Data([1]).write(to: d.appendingPathComponent("im.wav"))
        #expect(SkinStore(directory: d).url(for: .im)?.lastPathComponent == "im.wav")
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
        #expect(SoundCue.message.asset == .im)
        #expect(SoundCue.welcome.asset == .welcome)
        #expect(SoundCue.goodbye.asset == .goodbye)
    }
}
