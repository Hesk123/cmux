// Modified 2026-09-03 for the cmux carousel build (carousel unit work).
import Foundation
import Observation

/// Reads and watches `<dataRoot>/statusline-snapshots/` (CONTRACT rows 76, 91, 118).
///
/// Row 76 owns the staleness bound: a snapshot older than `maxAge` (60 s) is
/// **stale**, and the top bar renders the stale state rather than a confidently
/// wrong number. `refreshInterval` in `settings.json` keeps an idle session
/// emitting; this bound covers what that cannot — the ssh bridge being down, the
/// session having exited, or Claude Code simply not running in that pane.
@MainActor
@Observable
final class StatuslineSnapshotStore {
    /// Row 76.
    static let maxAge: TimeInterval = 60

    private(set) var records: [String: StatuslineSnapshotRecord] = [:]
    /// Set when the snapshots directory could not be read at all, so the top bar
    /// can distinguish "no snapshot for this session" from "no snapshot source".
    private(set) var directoryIsReadable = false
    private(set) var lastReloadedAt: Date?

    let dataRoot: CarouselDataRoot

    private let fileManager: FileManager
    private let now: @Sendable () -> Date
    private var watcher: DirectoryWatcher?
    private var pollTask: Task<Void, Never>?

    init(
        dataRoot: CarouselDataRoot,
        fileManager: FileManager = .default,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.dataRoot = dataRoot
        self.fileManager = fileManager
        self.now = now
    }

    func record(forSessionId sessionId: String?) -> StatuslineSnapshotRecord? {
        guard let sessionId, CarouselDataRoot.isPathSafeIdentifier(sessionId) else { return nil }
        return records[sessionId]
    }

    /// Row 91: N = 2 s locally. The directory watch reacts immediately; the poll
    /// is the floor that also re-evaluates staleness while nothing changes on
    /// disk, which is exactly the case row 76 exists for.
    func start(pollInterval: Duration = .seconds(2)) {
        reload()
        watcher = DirectoryWatcher(url: dataRoot.statuslineSnapshotsDirectory) { [weak self] in
            self?.reload()
        }
        pollTask?.cancel()
        // No `deinit` cancels this: touching @MainActor state from a nonisolated
        // deinit is an isolation violation. The weak self check terminates the
        // loop when the store is deallocated, so the task cannot outlive it.
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: pollInterval)
                guard !Task.isCancelled, let self else { return }
                self.reload()
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        watcher = nil
    }

    func reload() {
        let directory = dataRoot.statuslineSnapshotsDirectory
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else {
            directoryIsReadable = false
            records = [:]
            lastReloadedAt = now()
            return
        }
        directoryIsReadable = true
        var loaded: [String: StatuslineSnapshotRecord] = [:]
        for name in names where name.hasSuffix(".json") && !name.hasPrefix(".") {
            let sessionId = String(name.dropLast(".json".count))
            guard CarouselDataRoot.isPathSafeIdentifier(sessionId) else { continue }
            let url = directory.appending(path: name)
            guard let data = try? Data(contentsOf: url) else { continue }
            let modified = (try? fileManager.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
            guard let record = try? StatuslineSnapshotRecord.decode(
                data: data,
                fileModificationDate: modified
            ) else { continue }
            loaded[sessionId] = record
        }
        records = loaded
        lastReloadedAt = now()
    }
}

/// `DispatchSource` directory watch. GCD is the right tool here: this is a
/// kqueue-backed file-descriptor source with no async equivalent, and it is the
/// pattern already used in `Sources/CmuxConfig.swift` and the ComputerUse stores.
private final class DirectoryWatcher {
    private let descriptor: CInt
    private let source: DispatchSourceFileSystemObject

    init?(url: URL, onChange: @escaping @Sendable @MainActor () -> Void) {
        // Watching a directory that does not exist yet is a normal state on a
        // machine whose mirror has not run, so this is a nil return, not a crash.
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        descriptor = fd
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { MainActor.assumeIsolated { onChange() } }
        source.setCancelHandler { [descriptor] in close(descriptor) }
        source.resume()
    }

    deinit { source.cancel() }
}
