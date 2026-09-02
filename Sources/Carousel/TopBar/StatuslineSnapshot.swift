import Foundation

/// The Claude Code statusline payload, as teed to
/// `<dataRoot>/statusline-snapshots/<session_id>.json` by
/// `tools/statusline-snapshot/statusline-command.sh` (CONTRACT row 76).
///
/// **Every optional is actually optional**, which is not defensive padding — a
/// real payload captured on the Hive on 2026-09-02 (row 120's probe) carried no
/// `vim`, `agent`, `pr` or `worktree` key at all, carried three keys the research
/// doc does not list (`scratchpad_dir`, `output_style`, `prompt_cache`), and
/// reported `context_window_size` as 1_000_000 rather than the documented 200_000
/// default. Unknown keys are ignored by `Codable`; missing keys must not throw.
///
/// Percentages decode as `Double` because the live payload emits them as JSON
/// integers (`49`) while the contract's fixtures use fractions (`63.4`).
struct StatuslineSnapshot: Decodable, Equatable, Sendable {
    let sessionId: String?
    let sessionName: String?
    let transcriptPath: String?
    let model: Model?
    let contextWindow: ContextWindow?
    let rateLimits: RateLimits?
    /// Added by our own tee; absent from a snapshot written by anything else.
    let carousel: CarouselMeta?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case sessionName = "session_name"
        case transcriptPath = "transcript_path"
        case model
        case contextWindow = "context_window"
        case rateLimits = "rate_limits"
        case carousel = "_carousel"
    }

    struct Model: Decodable, Equatable, Sendable {
        let id: String?
        let displayName: String?

        enum CodingKeys: String, CodingKey {
            case id
            case displayName = "display_name"
        }
    }

    struct ContextWindow: Decodable, Equatable, Sendable {
        let contextWindowSize: Int?
        let usedPercentage: Double?
        let totalInputTokens: Int?
        let totalOutputTokens: Int?
        /// `null` before the first API call and again right after `/compact`
        /// until the next response repopulates it. Row 13 requires a defined
        /// empty state here, never a zero.
        let currentUsage: CurrentUsage?

        enum CodingKeys: String, CodingKey {
            case contextWindowSize = "context_window_size"
            case usedPercentage = "used_percentage"
            case totalInputTokens = "total_input_tokens"
            case totalOutputTokens = "total_output_tokens"
            case currentUsage = "current_usage"
        }
    }

    struct CurrentUsage: Decodable, Equatable, Sendable {
        let inputTokens: Int?
        let outputTokens: Int?
        let cacheCreationInputTokens: Int?
        let cacheReadInputTokens: Int?

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case cacheCreationInputTokens = "cache_creation_input_tokens"
            case cacheReadInputTokens = "cache_read_input_tokens"
        }
    }

    struct RateLimits: Decodable, Equatable, Sendable {
        let fiveHour: Window?
        let sevenDay: Window?

        enum CodingKeys: String, CodingKey {
            case fiveHour = "five_hour"
            case sevenDay = "seven_day"
        }
    }

    struct Window: Decodable, Equatable, Sendable {
        let usedPercentage: Double?
        /// Epoch seconds.
        let resetsAt: Double?

        enum CodingKeys: String, CodingKey {
            case usedPercentage = "used_percentage"
            case resetsAt = "resets_at"
        }

        var resetDate: Date? { resetsAt.map(Date.init(timeIntervalSince1970:)) }
    }

    struct CarouselMeta: Decodable, Equatable, Sendable {
        let capturedAt: Double?
        let host: String?
        let schema: Int?

        enum CodingKeys: String, CodingKey {
            case capturedAt = "captured_at"
            case host
            case schema
        }

        var capturedDate: Date? { capturedAt.map(Date.init(timeIntervalSince1970:)) }
    }
}

extension StatuslineSnapshot.ContextWindow {
    /// Input-side tokens actually occupying the window. The statusline's own
    /// `used_percentage` is computed from input tokens only, so the derived
    /// token label (row 13) uses the same basis rather than inventing a second.
    var usedInputTokens: Int? {
        guard let usage = currentUsage else { return nil }
        let parts = [usage.inputTokens, usage.cacheCreationInputTokens, usage.cacheReadInputTokens]
        let present = parts.compactMap(\.self)
        return present.isEmpty ? nil : present.reduce(0, +)
    }
}
