import Darwin
import Foundation

/// Watches one session's `subagents/` directory and reports a fresh scan.
///
/// Two mechanisms, because one is not enough. A `DispatchSource` file-system
/// watch fires when the directory's contents change, which covers an agent
/// being spawned. It does **not** fire when an existing transcript is appended
/// to, and appending is exactly what a working agent does — so a poll runs
/// alongside it and is what actually moves an agent between running, finished
/// and unknown (CONTRACT rows 71 and 127).
///
/// Scans run on the watcher's serial queue and the result is handed back on the
/// main actor, so no file I/O happens on the UI thread.
@MainActor
final class SubAgentDirectoryWatcher {
    private let policy: SubAgentLivenessPolicy
    private let onScan: @MainActor (SubAgentScan) -> Void

    // DispatchSource requires a delivery queue; every mutation hops back to
    // MainActor, matching `ComputerUseMenuBarSnapshotStore`.
    private let queue = DispatchQueue(label: "com.cmuxterm.app.carouselSubAgentsWatch")
    private var directoryWatchSource: DispatchSourceFileSystemObject?
    private var directoryWatchToken: SubAgentWatchToken?
    private var pollToken: SubAgentWatchToken?
    private var root: CarouselDataRoot?
    private var session: SubAgentsSessionKey?
    private var probeCache: [String: SubAgentTranscriptProbe.CacheEntry] = [:]
    private var scanGeneration = 0
    private var coalesceTask: Task<Void, Never>?

    init(
        policy: SubAgentLivenessPolicy = .default,
        onScan: @escaping @MainActor (SubAgentScan) -> Void
    ) {
        self.policy = policy
        self.onScan = onScan
    }

    /// Points the watcher at a session, or at `nil` for a surface that is not a
    /// Claude Code session. Re-pointing discards the probe cache: the agent ids
    /// of one session mean nothing in another.
    func watch(root: CarouselDataRoot, session: SubAgentsSessionKey?) {
        // Compare the location, not the whole value. `CarouselDataRoot` carries a
        // freshness stamp that changes on every resolve, so comparing the values
        // would tear down and rebuild the watch on every update — cancelling the
        // poll, dropping the probe cache and re-reading every transcript, once a
        // second, forever.
        let unchanged = root.url == self.root?.url && session == self.session && pollToken != nil
        guard !unchanged else { return }
        stop()
        self.root = root
        self.session = session
        probeCache = [:]
        scanNow()
        guard session != nil else { return }
        startDirectoryWatch()
        startPolling()
    }

    /// Cancels both mechanisms. Releasing the watcher does the same thing, via
    /// the tokens, so a caller that forgets this does not leak a descriptor.
    func stop() {
        coalesceTask?.cancel()
        coalesceTask = nil
        directoryWatchSource = nil
        directoryWatchToken = nil
        pollToken = nil
        scanGeneration &+= 1
    }

    /// Runs one scan off the main actor and delivers it back on the main actor.
    func scanNow() {
        guard let root else { return }
        scanGeneration &+= 1
        let generation = scanGeneration
        let session = session
        let policy = policy
        let cache = probeCache

        queue.async { [weak self] in
            let result = SubAgentDirectoryScanner.scan(
                root: root,
                session: session,
                now: Date(),
                policy: policy,
                cache: cache
            )
            Task { @MainActor [weak self] in
                guard let self, generation == self.scanGeneration else { return }
                self.probeCache = result.cache
                self.onScan(result.scan)
            }
        }
    }

    /// Collapses the burst of events a single spawn produces (the transcript
    /// and its metadata file land moments apart) into one scan.
    private func scheduleCoalescedScan() {
        guard coalesceTask == nil else { return }
        let window = policy.coalesceWindow
        coalesceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(window))
            guard let self, !Task.isCancelled else { return }
            self.coalesceTask = nil
            self.scanNow()
        }
    }

    private var watchedDirectoryURL: URL? {
        guard let root, let session else { return nil }
        return root.subAgentsDirectory(
            projectSlug: session.projectSlug,
            sessionID: session.sessionID
        )
    }

    private func startDirectoryWatch() {
        guard directoryWatchSource == nil, let url = watchedDirectoryURL else { return }
        let descriptor = open(url.path, O_EVTONLY | O_CLOEXEC)
        // A directory that does not exist yet is normal: the session has not
        // spawned an agent. The poll re-arms the watch once it appears.
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .attrib, .link, .rename, .delete],
            queue: queue
        )
        source.setEventHandler(handler: Self.makeEventHandler(source: source, watcher: self))
        source.setCancelHandler(handler: Self.makeCancelHandler(descriptor: descriptor))
        source.resume()
        directoryWatchSource = source
        directoryWatchToken = SubAgentWatchToken { source.cancel() }
    }

    private func startPolling() {
        guard pollToken == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + policy.pollInterval, repeating: policy.pollInterval)
        timer.setEventHandler(handler: Self.makePollHandler(watcher: self))
        timer.resume()
        pollToken = SubAgentWatchToken { timer.cancel() }
    }

    /// DispatchSource delivers on its own queue. Build the callbacks outside the
    /// main actor so Swift 6 does not trap before the explicit actor hop.
    private nonisolated static func makeEventHandler(
        source: DispatchSourceFileSystemObject,
        watcher: SubAgentDirectoryWatcher
    ) -> @Sendable () -> Void {
        { [weak source, weak watcher] in
            guard let source else { return }
            let events = source.data
            Task { @MainActor [weak watcher] in
                watcher?.handleDirectoryEvent(events, from: source)
            }
        }
    }

    private nonisolated static func makeCancelHandler(descriptor: Int32) -> @Sendable () -> Void {
        { Darwin.close(descriptor) }
    }

    private nonisolated static func makePollHandler(
        watcher: SubAgentDirectoryWatcher
    ) -> @Sendable () -> Void {
        { [weak watcher] in
            Task { @MainActor [weak watcher] in
                watcher?.handlePollTick()
            }
        }
    }

    private func handleDirectoryEvent(
        _ events: DispatchSource.FileSystemEvent,
        from source: DispatchSourceFileSystemObject
    ) {
        guard directoryWatchSource === source else { return }
        // The directory itself was replaced — the mirror does this on a full
        // resync. Re-arm on the new inode, or the watch is dead but silent.
        if events.contains(.delete) || events.contains(.rename) {
            directoryWatchSource = nil
            directoryWatchToken = nil
            startDirectoryWatch()
        }
        scheduleCoalescedScan()
    }

    private func handlePollTick() {
        // Re-arm a watch that could not open its directory earlier, now that
        // the session may have created it.
        if directoryWatchSource == nil, session != nil {
            startDirectoryWatch()
        }
        scanNow()
    }
}
