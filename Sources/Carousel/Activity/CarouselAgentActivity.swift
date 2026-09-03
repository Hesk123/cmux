import Foundation

/// CONTRACT row 127 — the agent-running signal, with a named mechanism and a
/// stated latency, feeding rows 49, 65, 66 and 71 as well as the top bar.
///
/// Primary mechanism is `CarouselSessionStateReader`, which reads the session
/// registry's own `status` field. This type is the FALLBACK, used when the
/// registry is unreadable, and it is also the only mechanism available for
/// sub-agents, whose `.meta.json` files carry no status field at all (upstream
/// cmux issue #1152).
///
/// Latency budget: **≤ 1 s** — a `DispatchSource` write watch on the transcript
/// fires in milliseconds and a 1 s poll is the floor beneath it.
///
/// Max age: **120 s**, past which the signal is `.unknown` and never `.idle`.
/// Corroborated independently by U4 against 25 live Hive sub-agent transcripts:
/// 9,238 consecutive inter-write gaps measured p50 1.8 s, p90 12.7 s, p99 75.3 s,
/// p99.5 159.5 s. A shorter bound would report unknown constantly; a much longer
/// one would let an exited session keep reading as running.
enum CarouselAgentActivity: Equatable, Sendable {
    case running
    case idle
    /// The transcript is unreadable, has no conversational entry, or is older than
    /// `staleAfter`.
    case unknown
}

enum CarouselAgentActivityReader {
    static let latencyBudget: Duration = .seconds(1)
    static let staleAfter: TimeInterval = 120

    /// Entry types that are bookkeeping, not conversation. Measured on a real
    /// 6,178-entry Hive transcript: the final line is very often one of these
    /// rather than a message, so a reader that classifies the literal last line
    /// reports `.unknown` most of the time.
    static let bookkeepingTypes: Set<String> = [
        "attachment", "queue-operation", "system", "last-prompt",
        "ai-title", "mode", "permission-mode", "summary", "compact_boundary",
    ]

    static func activity(
        transcriptPath: String?,
        now: Date,
        fileManager: FileManager = .default,
        tailByteCount: Int = 256 * 1024
    ) -> CarouselAgentActivity {
        guard let transcriptPath, !transcriptPath.isEmpty else { return .unknown }
        let url = URL(fileURLWithPath: transcriptPath)
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let modified = attributes[.modificationDate] as? Date else { return .unknown }
        if now.timeIntervalSince(modified) > staleAfter { return .unknown }
        return classify(lastConversationalEntry(url: url, tailByteCount: tailByteCount))
    }

    /// What the last real message in the transcript says about the turn.
    ///
    /// Role alone cannot answer this, which is the defect U4 found and measured.
    /// On a real transcript the shapes are: `assistant` carrying only `tool_use`
    /// (39 occurrences), `assistant` carrying only `thinking` (30), `assistant`
    /// carrying only `text` (33), and `user` carrying `tool_result` (39) or a bare
    /// string (33). Only the third of those is turn-final. Classifying `assistant`
    /// as idle would report an agent that is mid-tool-call as doing nothing.
    static func classify(_ entry: Entry?) -> CarouselAgentActivity {
        guard let entry else { return .unknown }
        switch entry.type {
        case "assistant":
            if entry.blockTypes.contains("tool_use") { return .running }
            if entry.blockTypes.contains("thinking") { return .running }
            if entry.blockTypes.contains("text") { return .idle }
            return .unknown
        case "user":
            // A tool_result means a tool just returned and the model will continue;
            // a bare string means a prompt was just submitted. Both are in-flight.
            return .running
        default:
            return .unknown
        }
    }

    struct Entry: Equatable {
        let type: String
        let blockTypes: Set<String>
    }

    /// The last `user` or `assistant` entry, skipping bookkeeping lines.
    ///
    /// Reads a bounded tail rather than the whole file: a session transcript reaches
    /// tens of megabytes and this is evaluated on every reload.
    static func lastConversationalEntry(url: URL, tailByteCount: Int = 256 * 1024) -> Entry? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd() else { return nil }
        let length = UInt64(max(tailByteCount, 1))
        let offset = end > length ? end - length : 0
        guard (try? handle.seek(toOffset: offset)) != nil,
              let data = try? handle.readToEnd(),
              let text = String(data: data, encoding: .utf8) else { return nil }
        var lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        // When the read started mid-file the first line is probably a fragment.
        if offset > 0, !lines.isEmpty { lines.removeFirst() }
        for line in lines.reversed() {
            guard let lineData = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let type = object["type"] as? String,
                  !bookkeepingTypes.contains(type)
            else { continue }
            guard type == "user" || type == "assistant" else { continue }
            return Entry(type: type, blockTypes: blockTypes(of: object))
        }
        return nil
    }

    static func blockTypes(of object: [String: Any]) -> Set<String> {
        let content = (object["message"] as? [String: Any])?["content"] ?? object["content"]
        if let blocks = content as? [[String: Any]] {
            return Set(blocks.compactMap { $0["type"] as? String })
        }
        if content is String { return ["text"] }
        return []
    }
}
