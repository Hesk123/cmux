// Modified 2026-09-03 for the cmux carousel build (carousel unit work).
import Foundation

/// Reads `<dataRoot>/sessions/*.json`, Claude Code's own per-process session
/// registry. Verified live on the Hive 2026-09-02.
///
/// **This is a better mechanism than CONTRACT row 127 assumed, and the evidence
/// is recorded here rather than left implicit.** Row 127 specifies a watcher on
/// the transcript's last-message role because "the sub-agent `.meta.json` files
/// carry no status field at all". That is true of sub-agents and remains the
/// mechanism for row 71's per-agent count. It is not true of the *session*: each
/// `sessions/<pid>.json` carries a first-class `status` of `busy` or `idle`,
/// alongside `sessionId` — which is exactly the statusline snapshot's filename,
/// making this the row-125 join — and `tmux`, which is D-4's card-to-session key.
///
/// Deliberately NOT inferred: liveness from `updatedAt`. A session file observed
/// on the Hive had an `updatedAt` 6.7 days old and a live pid, so an age bound
/// would have reported a healthy long-lived session as dead. `pid` is equally
/// useless across the mirror, being a Hive pid the Mac cannot check. Presence in
/// the mirror is therefore the only honest liveness signal, and absence of the
/// whole directory reports `.unknown` rather than marking every session dead.
struct CarouselSessionState: Equatable, Sendable {
    let sessionId: String
    let name: String?
    let cwd: String?
    /// `busy` or `idle` as written by Claude Code; any other value is preserved.
    let status: String?
    /// tmux target, e.g. `hive-claude:@10.%10` — D-4's card-to-session join.
    let tmuxTarget: String?
    let updatedAt: Date?

    var activity: CarouselAgentActivity {
        switch status {
        case "busy": .running
        case "idle": .idle
        default: .unknown
        }
    }
}

enum CarouselSessionPresence: Equatable, Sendable {
    case present(CarouselSessionState)
    /// The registry was readable and this session is not in it.
    case gone
    /// The registry could not be read — mirror down, or no sessions directory.
    case unknown
}

// Deliberately NOT Sendable: it holds a FileManager, which Foundation does not
// guarantee as Sendable, and nothing needs this type to cross an isolation
// boundary. Declaring the conformance anyway would be exactly the
// silence-the-diagnostic move row 110's gate exists to catch.
struct CarouselSessionStateReader {
    let dataRoot: CarouselDataRoot
    private let fileManager: FileManager

    init(dataRoot: CarouselDataRoot, fileManager: FileManager = .default) {
        self.dataRoot = dataRoot
        self.fileManager = fileManager
    }

    /// All sessions in the registry, keyed by Claude Code `sessionId`.
    /// Returns `nil` when the registry itself could not be read, which is the
    /// difference between "no sessions" and "no source".
    func readAll() -> [String: CarouselSessionState]? {
        let directory = dataRoot.sessionsDirectory
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return nil }
        var states: [String: CarouselSessionState] = [:]
        for name in names where name.hasSuffix(".json") && !name.hasPrefix(".") {
            let url = directory.appending(path: name)
            guard let data = try? Data(contentsOf: url),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let sessionId = object["sessionId"] as? String,
                  !sessionId.isEmpty
            else { continue }
            let updatedMilliseconds = object["updatedAt"] as? Double
            states[sessionId] = CarouselSessionState(
                sessionId: sessionId,
                name: object["name"] as? String,
                cwd: object["cwd"] as? String,
                status: object["status"] as? String,
                tmuxTarget: object["tmux"] as? String,
                updatedAt: updatedMilliseconds.map { Date(timeIntervalSince1970: $0 / 1000) }
            )
        }
        return states
    }

    func presence(ofSessionId sessionId: String?) -> CarouselSessionPresence {
        guard let sessionId, !sessionId.isEmpty else { return .unknown }
        guard let states = readAll() else { return .unknown }
        if let state = states[sessionId] { return .present(state) }
        return .gone
    }
}
