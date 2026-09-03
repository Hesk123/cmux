// Modified 2026-09-03 for the cmux carousel build (carousel unit work).
import Foundation

/// Reads one session's `subagents/` directory into a `SubAgentScan`.
///
/// Pure and free of actor isolation on purpose: it does blocking file I/O and
/// runs on the watcher's serial queue, then hands a `Sendable` result back to
/// the main actor. Every path it touches is derived from the injected
/// `CarouselDataRoot`, so nothing here can reach the current user's home
/// directory (CONTRACT row 118).
enum SubAgentDirectoryScanner {
    /// The scan plus the probe cache to carry into the next one.
    struct Result: Sendable {
        let scan: SubAgentScan
        let cache: [String: SubAgentTranscriptProbe.CacheEntry]
    }

    /// The `agent-<id>.jsonl` glob, stated once.
    ///
    /// The suffix matters. Each agent has a paired `agent-<id>.meta.json`, so a
    /// bare `agent-*` glob counts every agent twice (CONTRACT row 11).
    private static let transcriptPrefix = "agent-"
    private static let transcriptSuffix = ".jsonl"
    private static let metadataSuffix = ".meta.json"

    static func scan(
        root: CarouselDataRoot,
        session: SubAgentsSessionKey?,
        now: Date,
        policy: SubAgentLivenessPolicy,
        cache: [String: SubAgentTranscriptProbe.CacheEntry],
        fileManager: FileManager = .default
    ) -> Result {
        // Read in the same off-main pass as the directory: the freshness of
        // this reading is part of the reading.
        let freshness = CarouselDataRoot.mirrorFreshness(at: root.url, now: now)

        guard let session else {
            return Result(
                scan: .empty(availability: .outOfScope, scannedAt: now, freshness: freshness),
                cache: [:]
            )
        }

        guard fileManager.fileExists(atPath: root.url.path) else {
            return Result(
                scan: .empty(
                    availability: .rootMissing(root.url.path),
                    scannedAt: now,
                    freshness: freshness
                ),
                cache: [:]
            )
        }

        let directory = root.subAgentsDirectory(
            projectSlug: session.projectSlug,
            sessionID: session.sessionID
        )

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return Result(
                scan: .empty(
                    availability: .sessionMissing,
                    scannedAt: now,
                    freshness: freshness
                ),
                cache: [:]
            )
        }

        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else {
            return Result(
                scan: .empty(
                    availability: .sessionMissing,
                    scannedAt: now,
                    freshness: freshness
                ),
                cache: [:]
            )
        }

        var records: [SubAgentRecord] = []
        var nextCache: [String: SubAgentTranscriptProbe.CacheEntry] = [:]
        records.reserveCapacity(entries.count / 2)

        for entry in entries {
            let fileName = entry.lastPathComponent
            guard fileName.hasPrefix(transcriptPrefix), fileName.hasSuffix(transcriptSuffix) else {
                continue
            }
            let agentID = String(
                fileName.dropFirst(transcriptPrefix.count).dropLast(transcriptSuffix.count)
            )
            guard !agentID.isEmpty else { continue }

            let values = try? entry.resourceValues(forKeys: Set(keys))
            let modifiedAt = values?.contentModificationDate ?? .distantPast
            let size = Int64(values?.fileSize ?? 0)

            // An unchanged transcript is not re-read. Without this a 1 s poll
            // would re-parse every file in a directory that reaches 180 of
            // them, most of which finished hours ago.
            let shape: SubAgentTranscriptProbe.Shape
            if let cached = cache[agentID], cached.modifiedAt == modifiedAt, cached.size == size {
                shape = cached.shape
            } else {
                shape = SubAgentTranscriptProbe.shape(
                    ofTranscriptAt: entry,
                    maximumTailBytes: policy.maximumTailBytes
                )
            }
            nextCache[agentID] = SubAgentTranscriptProbe.CacheEntry(
                modifiedAt: modifiedAt,
                size: size,
                shape: shape
            )

            let metadataURL = directory.appendingPathComponent(
                transcriptPrefix + agentID + metadataSuffix,
                isDirectory: false
            )
            let metadata = SubAgentMetadata.read(at: metadataURL)

            records.append(
                SubAgentRecord(
                    id: agentID,
                    name: metadata?.name,
                    agentType: metadata?.agentType,
                    taskDescription: metadata?.description,
                    model: metadata?.model,
                    spawnDepth: metadata?.spawnDepth ?? 0,
                    parentAgentID: metadata?.parentAgentId,
                    activity: policy.activity(shape: shape, modifiedAt: modifiedAt, now: now),
                    lastActivity: modifiedAt,
                    hasMetadata: metadata != nil
                )
            )
        }

        records.sort(by: SubAgentRecord.orderedBefore)
        return Result(
            scan: SubAgentScan(
                availability: .ready,
                records: records,
                scannedAt: now,
                freshness: freshness
            ),
            cache: nextCache
        )
    }
}
