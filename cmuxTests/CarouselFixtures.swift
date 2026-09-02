import Foundation

@testable import cmux

/// Fixtures for the U5 rows. These live in the test target and never ship
/// (CONTRACT harness H3).
enum CarouselFixtures {
    /// A statusline payload with every field the contract's rows address.
    static func snapshotJSON(
        sessionId: String,
        modelDisplayName: String? = "Claude Fable 5.1",
        contextUsedPercentage: Double? = 63.4,
        contextWindowSize: Int? = 200_000,
        includeCurrentUsage: Bool = true,
        fiveHourPercent: Double? = 62,
        sevenDayPercent: Double? = 41,
        includeRateLimits: Bool = true,
        transcriptPath: String? = nil,
        capturedAt: Date?
    ) -> Data {
        var object: [String: Any] = ["session_id": sessionId]
        if let modelDisplayName {
            object["model"] = ["id": "fixture-model", "display_name": modelDisplayName]
        }
        if let transcriptPath { object["transcript_path"] = transcriptPath }

        var contextWindow: [String: Any] = [:]
        if let contextUsedPercentage { contextWindow["used_percentage"] = contextUsedPercentage }
        if let contextWindowSize { contextWindow["context_window_size"] = contextWindowSize }
        contextWindow["current_usage"] = includeCurrentUsage
            ? [
                "input_tokens": 1_000,
                "output_tokens": 50,
                "cache_creation_input_tokens": 20,
                "cache_read_input_tokens": 125_780,
              ] as [String: Any]
            : NSNull()
        object["context_window"] = contextWindow

        if includeRateLimits {
            var limits: [String: Any] = [:]
            if let fiveHourPercent {
                limits["five_hour"] = ["used_percentage": fiveHourPercent, "resets_at": 1_788_400_800]
            }
            if let sevenDayPercent {
                limits["seven_day"] = ["used_percentage": sevenDayPercent, "resets_at": 1_788_984_000]
            }
            object["rate_limits"] = limits
        }
        if let capturedAt {
            object["_carousel"] = [
                "captured_at": capturedAt.timeIntervalSince1970,
                "host": "fixture-host",
                "schema": 1,
            ] as [String: Any]
        }
        // swiftlint:disable:next force_try - a fixture that cannot serialise is a
        // broken test, and failing loudly here is the intent.
        return try! JSONSerialization.data(withJSONObject: object)
    }

    /// A session registry entry, matching the live shape verified on the Hive
    /// on 2026-09-02.
    static func sessionRegistryJSON(sessionId: String, status: String, name: String = "fixture") -> Data {
        let object: [String: Any] = [
            "pid": 12_345,
            "sessionId": sessionId,
            "cwd": "/fixture",
            "startedAt": 1_788_344_578_213,
            "kind": "interactive",
            "tmux": "hive-claude:@10.%10",
            "name": name,
            "status": status,
            "updatedAt": 1_788_383_100_279,
        ]
        // swiftlint:disable:next force_try
        return try! JSONSerialization.data(withJSONObject: object)
    }

    /// The **real** payload captured on the Hive through the row-76 tee at
    /// 2026-09-02 21:54 UTC, paths and names redacted, shape untouched.
    ///
    /// This is row 120's evidence carried into the test target: it proves the
    /// parser survives the actual payload — the three keys the research doc does
    /// not list (`scratchpad_dir`, `output_style`, `prompt_cache`), integer
    /// percentages where the contract's fixtures use fractions, and a
    /// `context_window_size` of 1_000_000 rather than the documented default.
    /// A fixture-only suite would have made all four unaskable.
    static let realCapturedPayload = Data(realCapturedPayloadJSON.utf8)

    static let realCapturedPayloadJSON = """
    {
      "session_id": "32999e8f-c459-4e76-aed9-4f4b6e48df79",
      "transcript_path": "/redacted/for/fixture",
      "cwd": "/redacted/for/fixture",
      "scratchpad_dir": "/redacted/for/fixture",
      "prompt_id": "5fcdc0ea-00f6-4664-b1c7-9627b547fa98",
      "effort": { "level": "high" },
      "session_name": "redacted",
      "model": { "id": "claude-fable-5-1", "display_name": "Fable 5.1" },
      "workspace": { "current_dir": "/redacted/for/fixture", "project_dir": "/redacted/for/fixture" },
      "version": "2.1.258",
      "output_style": { "name": "default" },
      "cost": {
        "total_cost_usd": 1480.2913466000064, "total_duration_ms": 41550031,
        "total_api_duration_ms": 100991232, "total_lines_added": 25587, "total_lines_removed": 1402
      },
      "context_window": {
        "total_input_tokens": 457534, "total_output_tokens": 39,
        "context_window_size": 1000000,
        "current_usage": {
          "input_tokens": 4, "output_tokens": 39,
          "cache_creation_input_tokens": 1521, "cache_read_input_tokens": 456009
        },
        "used_percentage": 46, "remaining_percentage": 54
      },
      "exceeds_200k_tokens": true,
      "prompt_cache": {
        "warm": true, "caching_observed": true, "ttl": "1h", "expires_at": 1788389684,
        "requests": 602, "misses": 5, "expected_rebuilds": 1, "hit_ratio": 0.9914361526355306,
        "cache_write_tokens": 2531527, "miss_recache_tokens": 1190516,
        "last_miss_at": 1788383100, "recache_tokens_if_cold": 457534
      },
      "fast_mode": false,
      "thinking": { "enabled": true },
      "rate_limits": {
        "five_hour": { "used_percentage": 60, "resets_at": 1788400800 },
        "seven_day": { "used_percentage": 12, "resets_at": 1788984000 }
      },
      "_carousel": { "captured_at": 1788386086, "host": "hive-brain", "schema": 1 }
    }
    """

    static func session(claudeSessionId: String?, displayName: String = "card") -> CarouselSession {
        CarouselSession(
            panelId: UUID(),
            resourceId: "surface:\(displayName)",
            claudeSessionId: claudeSessionId,
            projectSlug: "-fixture",
            displayName: displayName,
            subtitle: "fixture"
        )
    }
}

/// A stand-in for U1's routing, so row 125's join is testable before U1 ships.
@MainActor
final class FakeCarouselSessionRouting: CarouselSessionRouting {
    var centredSession: CarouselSession?
    var onCentredSessionChanged: ((CarouselSession?) -> Void)?

    init(centredSession: CarouselSession?) {
        self.centredSession = centredSession
    }

    func centre(on session: CarouselSession?) {
        centredSession = session
        onCentredSessionChanged?(session)
    }
}
