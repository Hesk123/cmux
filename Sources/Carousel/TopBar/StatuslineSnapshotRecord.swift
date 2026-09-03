// Modified 2026-09-03 for the cmux carousel build (carousel unit work).
import Foundation

/// One parsed snapshot plus the capture time row 76's staleness bound is measured against.
struct StatuslineSnapshotRecord: Equatable, Sendable {
    let snapshot: StatuslineSnapshot
    /// Authoritative capture time.
    let capturedAt: Date
    /// `true` when `capturedAt` came from the payload's own `_carousel.captured_at`
    /// rather than the file's modification date. A mirror that does not preserve
    /// mtime would make every snapshot look permanently fresh, so the in-payload
    /// value is preferred and the fallback is recorded rather than hidden.
    let capturedAtIsAuthoritative: Bool

    static func decode(data: Data, fileModificationDate: Date?) throws -> StatuslineSnapshotRecord {
        let snapshot = try JSONDecoder().decode(StatuslineSnapshot.self, from: data)
        if let stamped = snapshot.carousel?.capturedDate {
            return StatuslineSnapshotRecord(
                snapshot: snapshot,
                capturedAt: stamped,
                capturedAtIsAuthoritative: true
            )
        }
        return StatuslineSnapshotRecord(
            snapshot: snapshot,
            capturedAt: fileModificationDate ?? .distantPast,
            capturedAtIsAuthoritative: false
        )
    }

    func age(now: Date) -> TimeInterval { now.timeIntervalSince(capturedAt) }
}
