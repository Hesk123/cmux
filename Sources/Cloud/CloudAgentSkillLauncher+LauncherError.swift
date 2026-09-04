// Modified 2026-09-04 for the Genesis rename (row-129 notice for the Sep-3 product-prose sweep).
import Foundation

extension CloudAgentSkillLauncher {
    enum LauncherError: LocalizedError {
        case skillResourceMissing

        var errorDescription: String? {
            switch self {
            case .skillResourceMissing:
                return String(
                    localized: "machines.agent.error.missingSkill",
                    defaultValue: "This build is missing the bundled Genesis Cloud skill file."
                )
            }
        }
    }
}
