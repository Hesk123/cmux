import Foundation

/// One line of the popover's list: a record plus how far it is indented.
struct SubAgentOutlineRow: Identifiable, Sendable, Equatable {
    let record: SubAgentRecord
    /// Tree depth, 0 for a root. Distinct from `record.spawnDepth`, which is
    /// what Claude Code recorded at spawn time; this is the depth within the
    /// agents this directory actually holds.
    let depth: Int

    var id: String { record.id }
}

/// Flattens sub-agents into the nested list the popover draws.
///
/// Claude Code records nesting two ways and they disagree in practice.
/// `spawnDepth` is an absolute number (0 for a named teammate, 1 for a direct
/// child of the session, deeper for a nested spawn) while `parentAgentId`
/// names the actual parent but appears on only a small minority of files —
/// 9 of 180 in the session measured on 2026-09-02. The parent link is the
/// stronger signal where it exists, so it wins; `spawnDepth` is what the row
/// falls back to and is what CONTRACT row 11 asserts alongside it.
enum SubAgentOutline {
    static func rows(for records: [SubAgentRecord]) -> [SubAgentOutlineRow] {
        guard !records.isEmpty else { return [] }

        var childrenByParent: [String: [SubAgentRecord]] = [:]
        var roots: [SubAgentRecord] = []
        let knownIDs = Set(records.map(\.id))

        for record in records {
            // A parent id pointing outside this directory is not a parent here.
            // It happens whenever the parent's transcript has aged out, and the
            // child must still be shown rather than silently dropped.
            if let parentID = record.parentAgentID, parentID != record.id, knownIDs.contains(parentID) {
                childrenByParent[parentID, default: []].append(record)
            } else {
                roots.append(record)
            }
        }

        var rows: [SubAgentOutlineRow] = []
        rows.reserveCapacity(records.count)
        var visited = Set<String>()

        func append(_ record: SubAgentRecord, depth: Int) {
            // A cycle in the parent links would otherwise recurse forever. The
            // data should never contain one; the guard is cheap and the failure
            // it prevents is a hang in the UI process.
            guard visited.insert(record.id).inserted else { return }
            rows.append(SubAgentOutlineRow(record: record, depth: depth))
            for child in (childrenByParent[record.id] ?? []).sorted(by: SubAgentRecord.orderedBefore) {
                append(child, depth: depth + 1)
            }
        }

        for root in roots.sorted(by: SubAgentRecord.orderedBefore) {
            append(root, depth: 0)
        }

        // Anything a cycle kept out of the walk still gets a line.
        for record in records.sorted(by: SubAgentRecord.orderedBefore) where !visited.contains(record.id) {
            visited.insert(record.id)
            rows.append(SubAgentOutlineRow(record: record, depth: 0))
        }

        return rows
    }
}
