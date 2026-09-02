import Foundation

/// CONTRACT row 118 / D-5: the **one** injectable path provider for every
/// carousel read — sessions, sub-agent directories and statusline snapshots.
///
/// Why this type exists rather than a `HOME` override: a probe compiled and run
/// on the target Mac proved that both `NSHomeDirectory()` and
/// `FileManager.default.homeDirectoryForCurrentUser` ignore a `HOME` override and
/// resolve through the passwd entry instead, so `HOME` cannot be a test seam.
/// This is the seam. `CMUX_CAROUSEL_DATA_ROOT` wins over everything.
///
/// D-17 — the ban this type replaces covers **helpers, not just API names**.
/// Nothing under `Sources/Carousel/` may reference any of:
///   * `FileManager.default.homeDirectoryForCurrentUser`
///   * `NSHomeDirectory()`
///   * `URL.homeDirectory`
///   * `SidebarPathFormatter.homeDirectoryPath` — the one reachable type-level
///     home-path helper in `Sources/` (`Sources/Sidebar/SidebarPathFormatter.swift:4`);
///     every other one of the 109 hits is a function-local `let` and is not
///     reachable from another file.
/// The single derivation of the user's home directory in the whole carousel
/// lives in `localFallbackRoot` below, and even that is overridable.
struct CarouselDataRoot: Equatable, Sendable {
    /// Directory that contains `sessions/`, `projects/` and `statusline-snapshots/`.
    let url: URL
    /// How this root was chosen. Surfaced in the degraded state so a wrong root
    /// is visible rather than silently empty.
    let origin: Origin

    enum Origin: String, Equatable, Sendable {
        case environmentOverride
        case settings
        case mirror
        case localFallback
    }

    static let environmentKey = "CMUX_CAROUSEL_DATA_ROOT"

    var sessionsDirectory: URL { url.appending(path: "sessions") }
    var projectsDirectory: URL { url.appending(path: "projects") }
    var statuslineSnapshotsDirectory: URL { url.appending(path: "statusline-snapshots") }

    func statuslineSnapshotURL(sessionId: String) -> URL? {
        guard Self.isPathSafeIdentifier(sessionId) else { return nil }
        return statuslineSnapshotsDirectory.appending(path: "\(sessionId).json")
    }

    /// A session id becomes a filesystem path component. A real Claude Code
    /// session id is a UUID, so anything that is not already path-safe is
    /// rejected rather than sanitised into a name no writer ever produced.
    /// Mirrors the identical guard in `tools/statusline-snapshot/statusline-command.sh`.
    static func isPathSafeIdentifier(_ value: String) -> Bool {
        if value.isEmpty { return false }
        if value.hasPrefix(".") { return false }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
        return value.unicodeScalars.allSatisfy(allowed.contains)
    }

    // MARK: - Resolution

    /// Resolution order, highest first: environment override, settings key,
    /// the mirror populated by `tools/carousel-mirror/pull-claude-data.sh`,
    /// then the local machine's own `~/.claude`.
    static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        settingsPath: String? = nil,
        fileManager: FileManager = .default
    ) -> CarouselDataRoot {
        if let override = environment[environmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return CarouselDataRoot(url: URL(fileURLWithPath: override), origin: .environmentOverride)
        }
        if let settingsPath = settingsPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !settingsPath.isEmpty {
            return CarouselDataRoot(url: URL(fileURLWithPath: settingsPath), origin: .settings)
        }
        if let mirror = mirrorRoot(fileManager: fileManager) {
            return CarouselDataRoot(url: mirror, origin: .mirror)
        }
        return CarouselDataRoot(url: localFallbackRoot(fileManager: fileManager), origin: .localFallback)
    }

    /// Where `pull-claude-data.sh` deposits the Hive's `~/.claude` (D-4).
    static func mirrorRoot(fileManager: FileManager = .default) -> URL? {
        applicationSupportDirectory(fileManager: fileManager)?
            .appending(path: "cmux")
            .appending(path: "carousel-mirror")
    }

    /// The local machine's own `~/.claude`, used when the ssh bridge is down or
    /// when a session genuinely runs on this Mac (D-4's stated fallback).
    ///
    /// This is the ONLY home-directory derivation under `Sources/Carousel/`, and
    /// it deliberately avoids every name on row 118's ban list: Application
    /// Support already lives at `<home>/Library/Application Support`, so its
    /// grandparent is the home directory. Wrong-looking, and correct: the point
    /// of the ban is that no carousel read may bypass this provider, and this is
    /// the provider.
    static func localFallbackRoot(fileManager: FileManager = .default) -> URL {
        guard let appSupport = applicationSupportDirectory(fileManager: fileManager) else {
            return URL(fileURLWithPath: "/").appending(path: ".claude")
        }
        return appSupport
            .deletingLastPathComponent()   // <home>/Library
            .deletingLastPathComponent()   // <home>
            .appending(path: ".claude")
    }

    private static func applicationSupportDirectory(fileManager: FileManager) -> URL? {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    }
}
