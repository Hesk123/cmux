// Modified 2026-09-03 for the cmux carousel build (carousel unit work).
import Foundation

/// Reads the tail of a sub-agent transcript to decide whether its last message
/// looks like a final answer or like work in progress.
///
/// Only the tail is read. Transcripts reach megabytes and a session holds
/// nearly two hundred of them, so parsing whole files on a 1 s poll is not an
/// option; the scanner additionally skips any file whose size and modification
/// time are unchanged since the previous scan.
enum SubAgentTranscriptProbe {
    /// What the last complete JSON line in the transcript looks like.
    enum Shape: String, Sendable, Equatable {
        /// An assistant message carrying text and no tool call — the shape a
        /// finished agent's final report has.
        case terminalAssistantText
        /// Anything else: a tool call, a tool result, a user turn, a message
        /// that is only thinking.
        case working
        /// The file is empty, unreadable, or held no parseable JSON line within
        /// the read ceiling. Never treated as evidence either way.
        case indeterminate
    }

    /// One scan's memory of a transcript, so an unchanged file is not re-read.
    struct CacheEntry: Sendable, Equatable {
        let modifiedAt: Date
        let size: Int64
        let shape: Shape
    }

    /// Reads backwards from the end of the file until a complete JSON line
    /// parses, growing the window when a single line is larger than it.
    static func shape(ofTranscriptAt url: URL, maximumTailBytes: Int) -> Shape {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return .indeterminate }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd(), end > 0 else { return .indeterminate }

        var window = 64 * 1024
        while true {
            let offset = end > UInt64(window) ? end - UInt64(window) : 0
            guard (try? handle.seek(toOffset: offset)) != nil,
                  let data = try? handle.readToEnd(),
                  !data.isEmpty else {
                return .indeterminate
            }
            if let shape = shape(inTail: data) { return shape }
            // Nothing parsed. Either the window opened mid-line, or every line
            // in it is malformed. Grow once and retry; give up at the ceiling
            // or once the whole file has been read.
            if offset == 0 || window >= maximumTailBytes { return .indeterminate }
            window = min(window * 8, maximumTailBytes)
        }
    }

    /// Returns the shape of the last parseable line in `tail`, or `nil` when no
    /// line in it parsed — which tells the caller to read further back.
    ///
    /// Iterating from the end also handles the partially written last line that
    /// a live transcript always has: it simply fails to parse and the previous
    /// complete line is used.
    static func shape(inTail tail: Data) -> Shape? {
        let newline = UInt8(ascii: "\n")
        var lineEnd = tail.endIndex
        var index = tail.endIndex

        while index > tail.startIndex {
            index = tail.index(before: index)
            guard tail[index] == newline else { continue }
            let lineStart = tail.index(after: index)
            if lineStart < lineEnd, let shape = shape(ofLine: tail[lineStart..<lineEnd]) {
                return shape
            }
            lineEnd = index
        }

        // The window's first fragment may be a partial line; only trust it when
        // the caller has already read to the start of the file, which it proves
        // by there being no earlier newline to find.
        if tail.startIndex < lineEnd, let shape = shape(ofLine: tail[tail.startIndex..<lineEnd]) {
            return shape
        }
        return nil
    }

    private static func shape(ofLine line: Data) -> Shape? {
        guard !line.isEmpty else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else {
            return nil
        }
        return classify(object)
    }

    private static func classify(_ object: [String: Any]) -> Shape {
        guard object["type"] as? String == "assistant",
              let message = object["message"] as? [String: Any] else {
            return .working
        }

        if let blocks = message["content"] as? [[String: Any]] {
            let types = blocks.compactMap { $0["type"] as? String }
            // A final report is text with nothing left to run. A message that
            // is only `thinking`, or that carries a `tool_use`, is mid-turn.
            let hasText = types.contains("text")
            let hasToolUse = types.contains("tool_use")
            return hasText && !hasToolUse ? .terminalAssistantText : .working
        }

        if let text = message["content"] as? String, !text.isEmpty {
            return .terminalAssistantText
        }

        return .working
    }
}
