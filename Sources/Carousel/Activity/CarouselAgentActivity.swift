import Foundation

/// CONTRACT row 127 — the agent-running signal, with a named mechanism and a
/// stated latency, feeding rows 49, 65, 66 and 71 as well as the top bar.
///
/// Mechanism: upstream cmux issue #1152 records that per-turn running status is
/// missing, and the sub-agent `.meta.json` files carry no status field at all, so
/// there is nothing to read directly. The signal is derived instead from the
/// **role of the last entry in the session transcript**: Claude Code appends a
/// `user` entry when a turn is submitted and an `assistant` entry when the turn
/// completes, so a trailing `user` entry means a turn is in flight.
///
/// Latency budget: **≤ 1 s** — a `DispatchSource` write watch on the transcript
/// fires in milliseconds, and a 1 s poll is the floor beneath it.
///
/// Max age: **120 s**. Past that the signal renders `.unknown`, never `.idle`.
/// A single long turn can legitimately write nothing for minutes, so a shorter
/// bound would report unknown constantly; a much longer one would let an exited
/// session keep reading as running. Row 127 requires the bound to exist and be
/// stated, not to take a particular value.
enum CarouselAgentActivity: Equatable, Sendable {
    case running
    case idle
    /// The transcript is unreadable, empty, or older than `staleAfter`.
    case unknown
}

enum CarouselAgentActivityReader {
    static let latencyBudget: Duration = .seconds(1)
    static let staleAfter: TimeInterval = 120

    /// Reads the role of the transcript's last entry.
    ///
    /// A session transcript reaches tens of megabytes, so this reads a bounded
    /// tail from the end of the file rather than parsing the whole thing —
    /// `body` is evaluated on every reload and a full parse would dominate it.
    static func activity(
        transcriptPath: String?,
        now: Date,
        fileManager: FileManager = .default,
        tailByteCount: Int = 64 * 1024
    ) -> CarouselAgentActivity {
        guard let transcriptPath, !transcriptPath.isEmpty else { return .unknown }
        let url = URL(fileURLWithPath: transcriptPath)
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let modified = attributes[.modificationDate] as? Date else { return .unknown }
        if now.timeIntervalSince(modified) > staleAfter { return .unknown }
        guard let role = lastEntryRole(url: url, tailByteCount: tailByteCount) else { return .unknown }
        switch role {
        case "user": return .running
        case "assistant": return .idle
        default: return .unknown
        }
    }

    /// The `type` of the last complete JSON line in the file, or `nil`.
    static func lastEntryRole(url: URL, tailByteCount: Int = 64 * 1024) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd() else { return nil }
        let length = UInt64(max(tailByteCount, 1))
        let offset = end > length ? end - length : 0
        guard (try? handle.seek(toOffset: offset)) != nil,
              let data = try? handle.readToEnd(),
              let text = String(data: data, encoding: .utf8) else { return nil }
        // When the read started mid-file the first line may be a fragment, so it
        // is only trusted if the whole file fitted in the tail.
        var lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        if offset > 0, !lines.isEmpty { lines.removeFirst() }
        for line in lines.reversed() {
            guard let lineData = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { continue }
            if let type = object["type"] as? String { return type }
            if let role = object["role"] as? String { return role }
        }
        return nil
    }
}
