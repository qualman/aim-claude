import Foundation

/// Turns `claude --output-format stream-json` lines into app events.
/// Unknown or malformed lines are ignored. The reply comes only from the final `result` event.
public struct EventParser: Sendable {
    static let maxActivityLength = 80

    public init() {}

    public mutating func parse(line: String) -> [ClaudeEvent] {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String else { return [] }
        switch type {
        case "assistant":
            let content = (obj["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
            return content.compactMap { item in
                guard item["type"] as? String == "tool_use", let name = item["name"] as? String else { return nil }
                return .activity(Self.truncate(Self.describe(tool: name, input: item["input"] as? [String: Any] ?? [:])))
            }
        case "result":
            if obj["is_error"] as? Bool == true {
                let errors = (obj["errors"] as? [String])?.joined(separator: "; ")
                let text = (obj["result"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                return [.failure(errors ?? text ?? "Claude reported an error.")]
            }
            return [.reply(obj["result"] as? String ?? "")]
        default:
            return []
        }
    }

    static func describe(tool: String, input: [String: Any]) -> String {
        let file = (input["file_path"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent }
        switch tool {
        case "Read": return "Reading \(file ?? "a file")"
        case "Edit", "MultiEdit": return "Editing \(file ?? "a file")"
        case "Write": return "Writing \(file ?? "a file")"
        case "Bash": return "Running: \(input["command"] as? String ?? "a command")"
        case "Grep", "Glob": return "Searching for \(input["pattern"] as? String ?? "files")"
        case "WebFetch": return "Fetching \(input["url"] as? String ?? "a page")"
        case "WebSearch": return "Searching the web for \(input["query"] as? String ?? "something")"
        case "Task", "Agent": return "Starting a helper agent"
        default: return "Using \(tool)"
        }
    }

    static func truncate(_ s: String) -> String {
        let oneLine = s.replacingOccurrences(of: "\n", with: " ")
        guard oneLine.count > maxActivityLength else { return oneLine }
        return String(oneLine.prefix(maxActivityLength - 1)) + "…"
    }
}
