// Modified 2026-09-03 for the cmux carousel build (carousel unit work).
import Foundation

/// Every user-facing string the sub-agents surfaces show.
///
/// Collected here so the localization audit has one file to read, and so the
/// views stay free of catalog keys. `Localizable.xcstrings` carries no plural
/// variations anywhere in this project, so a count picks between two flat keys
/// rather than introducing the catalog's first plural entry.
enum SubAgentsStrings {
    static func chipCount(_ count: Int) -> String {
        count == 1
            ? String(localized: "carousel.subAgents.chip.countOne", defaultValue: "1 agent")
            : String(localized: "carousel.subAgents.chip.countOther", defaultValue: "\(count) agents")
    }

    static var chipAccessibilityLabel: String {
        String(localized: "carousel.subAgents.chip.accessibilityLabel", defaultValue: "Sub-agents")
    }

    static var popoverTitle: String {
        String(localized: "carousel.subAgents.popover.title", defaultValue: "Sub-agents")
    }

    static var empty: String {
        String(localized: "carousel.subAgents.empty", defaultValue: "No sub-agents yet")
    }

    static var outOfScope: String {
        String(localized: "carousel.subAgents.outOfScope", defaultValue: "Claude Code sessions only")
    }

    static var mirrorMissing: String {
        String(localized: "carousel.subAgents.mirrorMissing", defaultValue: "Mirror not found")
    }

    /// The chip has no room for a path; the popover does, and a degraded state
    /// that cannot say which directory is missing sends the reader hunting.
    static func mirrorMissingAt(path: String) -> String {
        String(
            localized: "carousel.subAgents.mirrorMissingAt",
            defaultValue: "No data root at \(path)"
        )
    }

    /// The host is named whenever the mirror knows it. A degraded state that
    /// cannot say which machine went quiet is not much of a degraded state.
    static func mirrorStale(host: String?) -> String {
        guard let host, !host.isEmpty else {
            return String(
                localized: "carousel.subAgents.mirrorStaleUnknownHost",
                defaultValue: "Mirrored data is stale"
            )
        }
        return String(
            localized: "carousel.subAgents.mirrorStale",
            defaultValue: "Data from \(host) is stale"
        )
    }

    static func excludedWorkspaces(_ count: Int) -> String {
        count == 1
            ? String(
                localized: "carousel.subAgents.excludedOne",
                defaultValue: "1 workspace not mounted"
            )
            : String(
                localized: "carousel.subAgents.excludedOther",
                defaultValue: "\(count) workspaces not mounted"
            )
    }

    static func unnamedAgent(_ shortID: String) -> String {
        String(localized: "carousel.subAgents.unnamedAgent", defaultValue: "Agent \(shortID)")
    }

    static var noDescription: String {
        String(localized: "carousel.subAgents.noDescription", defaultValue: "No description")
    }

    static var noMetadata: String {
        String(
            localized: "carousel.subAgents.noMetadata",
            defaultValue: "Metadata not written yet"
        )
    }

    static func activity(_ activity: SubAgentRecord.Activity) -> String {
        switch activity {
        case .running:
            String(localized: "carousel.subAgents.activity.running", defaultValue: "Running")
        case .finished:
            String(localized: "carousel.subAgents.activity.finished", defaultValue: "Finished")
        case .unknown:
            String(localized: "carousel.subAgents.activity.unknown", defaultValue: "Unknown")
        }
    }
}
