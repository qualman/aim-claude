import Foundation
import Testing
@testable import AIMCore

@Suite struct SkinStoreTests {
    private func dir() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("aim-skin-\(UUID().uuidString)")
        for sub in ["icons", "sounds", "fonts"] {
            try FileManager.default.createDirectory(at: d.appendingPathComponent(sub), withIntermediateDirectories: true)
        }
        return d
    }

    @Test func soundFoundByCueNameInAnyFormat() throws {
        let d = try dir()
        try Data([1]).write(to: d.appendingPathComponent("sounds/buddy-in.wav"))
        try Data([1]).write(to: d.appendingPathComponent("sounds/received.m4a"))
        let s = SkinStore(directory: d)
        #expect(s.sound(.buddyIn)?.lastPathComponent == "buddy-in.wav")
        #expect(s.sound(.received)?.lastPathComponent == "received.m4a")
        #expect(s.sound(.sent) == nil)
    }

    @Test func emptyOrMissingDirectoryHasNothing() throws {
        for s in [SkinStore(directory: try dir()), SkinStore(directory: URL(fileURLWithPath: "/tmp/aim-nope-\(UUID().uuidString)"))] {
            for c in SoundCue.allCases { #expect(s.sound(c) == nil) }
            #expect(s.icon("logo") == nil)
            #expect(s.fonts().isEmpty)
        }
    }

    @Test func smileysAreTheLineSizedFacesSortedByName() throws {
        let d = try dir()
        let sm = d.appendingPathComponent("icons/smileys")
        try FileManager.default.createDirectory(at: sm, withIntermediateDirectories: true)
        for f in ["wink-19.png", "smile-19.png", "smile-36.png", "frown-12.png"] { try Data([1]).write(to: sm.appendingPathComponent(f)) }
        #expect(SkinStore(directory: d).smileys().map(\.name) == ["smile", "wink"])
    }

    @Test func cueFileNames() {
        #expect(SoundCue.allCases.map(\.fileName) == ["buddy-in", "buddy-out", "received", "sent"])
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

    @Test func gifIconsWorkAndPNGWins() throws {
        let d = try dir()
        try Data([1]).write(to: d.appendingPathComponent("icons/tree-open.gif"))
        try Data([1]).write(to: d.appendingPathComponent("icons/logo.gif"))
        try Data([1]).write(to: d.appendingPathComponent("icons/logo.png"))
        let s = SkinStore(directory: d)
        #expect(s.icon("tree-open")?.lastPathComponent == "tree-open.gif")
        #expect(s.icon("logo")?.lastPathComponent == "logo.png")
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
