import Foundation
import Testing
@testable import AIMCore

private func events(_ fixture: String) throws -> [ClaudeEvent] {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Fixtures/\(fixture).jsonl")
    var parser = EventParser()
    return try String(contentsOf: url, encoding: .utf8)
        .split(separator: "\n").flatMap { parser.parse(line: String($0)) }
}

private func replies(_ e: [ClaudeEvent]) -> [String] {
    e.compactMap { if case .reply(let t) = $0 { t } else { nil } }
}

@Suite struct EventParserTests {
    @Test func toolTurnEmitsActivityThenOneReply() throws {
        let e = try events("tool-turn")
        #expect(e.first == .activity("Reading notes.txt"))
        #expect(replies(e).count == 1)
        #expect(replies(e)[0].hasPrefix("`notes.txt` has a single line"))
        #expect(e.last.map { if case .reply = $0 { true } else { false } } == true)
    }

    @Test func plainTurnEmitsOnlyReply() throws {
        let e = try events("plain-turn")
        #expect(e.count == 1)
        #expect(replies(e)[0].hasPrefix("Hey there"))
    }

    @Test func deniedTurnShowsAttemptAndReply() throws {
        let e = try events("denied-turn")
        #expect(e.first == .activity("Running: python3 -c \"print(6*7)\""))
        #expect(replies(e)[0].hasPrefix("Denied."))
    }

    @Test func errorResultIsFailure() throws {
        let e = try events("bad-resume")
        #expect(e.count == 1)
        guard case .failure = e[0] else { Issue.record("expected failure, got \(e)"); return }
    }

    @Test func garbageLinesAreIgnored() {
        var p = EventParser()
        #expect(p.parse(line: "not json").isEmpty)
        #expect(p.parse(line: "").isEmpty)
        #expect(p.parse(line: "[1,2]").isEmpty)
    }

    @Test func longActivityIsTruncatedTo80() {
        var p = EventParser()
        let cmd = String(repeating: "x", count: 200)
        let line = #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"\#(cmd)"}}]}}"#
        guard case .activity(let text) = p.parse(line: line).first else { Issue.record("no activity"); return }
        #expect(text.count == 80)
        #expect(text.hasSuffix("…"))
    }
}
