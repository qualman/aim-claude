import Foundation

public final class StateStore: Sendable {
    public let directory: URL
    private var file: URL { directory.appendingPathComponent("state.json") }

    public init(directory: URL) {
        self.directory = directory
    }

    /// Missing file means a fresh install. A corrupt file throws and is left alone.
    public func load() throws -> AppState {
        guard FileManager.default.fileExists(atPath: file.path) else { return AppState() }
        return try JSONDecoder().decode(AppState.self, from: Data(contentsOf: file))
    }

    public func save(_ state: AppState) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: file, options: .atomic)
    }
}
