import SwiftUI

/// One sub-agent in the popover: activity dot, name, task, and indentation for
/// a nested spawn.
///
/// Value in, view out. It holds no store reference, which is what keeps it
/// legal below the popover's lazy-stack boundary.
struct SubAgentRowView: View {
    let row: SubAgentOutlineRow
    let presentation: SubAgentsPresentation

    private var record: SubAgentRecord { row.record }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: presentation.chipSpacing) {
            activityDot
            VStack(alignment: .leading, spacing: 2) {
                Text(record.displayTitle)
                    .font(.system(size: presentation.rowTitleSize, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .accessibilityIdentifier("carousel.subAgents.row.\(record.id).title")
                Text(record.displaySubtitle)
                    .font(.system(size: presentation.rowSubtitleSize))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let model = record.model, !model.isEmpty {
                    // Which model an agent runs on is per-agent state the
                    // reference has no vocabulary for, and it is already in the
                    // metadata. Same type token as the subtitle, no new size.
                    Text(model)
                        .font(.system(size: presentation.rowSubtitleSize))
                        .foregroundStyle(.tertiary)
                        .accessibilityIdentifier("carousel.subAgents.row.\(record.id).model")
                }
            }
            Spacer(minLength: 0)
        }
        // Indentation is the nesting. Clamped so a deep chain cannot push a
        // row's text off the panel.
        .padding(.leading, presentation.rowIndent * CGFloat(min(row.depth, 3)))
        .accessibilityIdentifier("carousel.subAgents.row.\(record.id)")
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    /// Colour alone must not carry the state, so the dot changes shape as well:
    /// filled for running, hollow for finished, dashed for unknown.
    private var activityDot: some View {
        Image(systemName: dotSymbol)
            .font(.system(size: presentation.statusDotSize + 3, weight: .semibold))
            .foregroundStyle(dotColor)
            .accessibilityHidden(true)
    }

    private var dotSymbol: String {
        switch record.activity {
        case .running: "circle.fill"
        case .finished: "circle"
        case .unknown: "circle.dotted"
        }
    }

    private var dotColor: Color {
        switch record.activity {
        case .running: .green
        case .finished: .secondary
        case .unknown: .orange
        }
    }

    private var accessibilityLabel: String {
        "\(record.displayTitle), \(SubAgentsStrings.activity(record.activity)). \(record.displaySubtitle)"
    }
}

#if DEBUG
extension SubAgentRecord {
    /// Fixtures for previews only. Never referenced from shipping code paths;
    /// CONTRACT row 85 forbids mock data reaching the running app.
    static var previewRecords: [SubAgentRecord] {
        let now = Date()
        return [
            SubAgentRecord(
                id: "acmux-maker-U4-e892f8919e8b46f5",
                name: "cmux-maker-U4",
                agentType: "cmux-maker-U4",
                taskDescription: "Sub-agents chip and popover",
                model: "fable",
                spawnDepth: 0,
                parentAgentID: nil,
                activity: .running,
                lastActivity: now,
                hasMetadata: true
            ),
            SubAgentRecord(
                id: "a67a9e4f38de8dd16",
                name: nil,
                agentType: "general-purpose",
                taskDescription: "Contrast fix on the claim screen",
                model: "sonnet",
                spawnDepth: 1,
                parentAgentID: "acmux-maker-U4-e892f8919e8b46f5",
                activity: .running,
                lastActivity: now.addingTimeInterval(-4),
                hasMetadata: true
            ),
            SubAgentRecord(
                id: "af1d1edda8a2a9f82",
                name: nil,
                agentType: "gemini-researcher",
                taskDescription: "Fresh Polish YouTube landscape check",
                model: nil,
                spawnDepth: 1,
                parentAgentID: nil,
                activity: .finished,
                lastActivity: now.addingTimeInterval(-3_600),
                hasMetadata: true
            ),
        ]
    }
}

#Preview("Sub-agent row") {
    VStack(alignment: .leading, spacing: 10) {
        ForEach(SubAgentOutline.rows(for: SubAgentRecord.previewRecords)) { row in
            SubAgentRowView(row: row, presentation: .standard(width: 1344))
        }
    }
    .padding(40)
    .background(.black)
}
#endif
