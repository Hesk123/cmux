import Foundation

/// The statusline-snapshot half of the row-118 seam, added beside U7's provider
/// rather than inside it, so ownership stays clean and neither unit has to edit
/// the other's file.
extension CarouselDataRoot {
    /// A session id becomes a filesystem path component. A real Claude Code session
    /// id is a UUID and never needs sanitising, so anything that is not already
    /// path-safe is REJECTED rather than mangled into a name no writer produced.
    /// The identical rule is enforced on the Hive by
    /// `tools/statusline-snapshot/statusline-command.sh`, so the two ends of the
    /// pipe agree on what a valid filename is.
    static func isPathSafeIdentifier(_ value: String) -> Bool {
        if value.isEmpty { return false }
        if value.hasPrefix(".") { return false }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
        return value.unicodeScalars.allSatisfy(allowed.contains)
    }

    /// Nil for any id that is not path-safe, so a bad id cannot become a read
    /// outside `statuslineSnapshotsDirectory`.
    func statuslineSnapshotURL(sessionId: String) -> URL? {
        guard Self.isPathSafeIdentifier(sessionId) else { return nil }
        return statuslineSnapshotsDirectory.appending(path: "\(sessionId).json")
    }

    /// Row 117's degraded state, phrased for the top bar. Names the host when the
    /// mirror's own stamp knows it, so a user is told which machine they are
    /// looking at rather than shown an unexplained blank.
    var degradedDescription: String {
        switch (source, freshness) {
        case (.mirror, .stale(let age, let host)):
            "Mirror of \(host ?? "the Hive") is \(Int(age.rounded()))s stale at \(url.path)"
        case (.mirror, .unknown):
            "Mirror has never completed a pull at \(url.path)"
        case (.mirror, .fresh):
            "Mirror is fresh but unreadable at \(url.path)"
        case (.environmentOverride, _):
            "Injected data root is unreadable at \(url.path)"
        case (.setting, _):
            "Configured data root is unreadable at \(url.path)"
        case (.localFallback, _):
            "Local data root is unreadable at \(url.path)"
        }
    }
}
