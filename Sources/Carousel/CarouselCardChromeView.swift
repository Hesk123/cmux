// GPL-3.0-or-later modified-file notice (CONTRACT row 129):
// Modified 2026-09-02 for the cmux carousel UI (unit U1: track geometry, card shell,
// session data source, live/snapshot swap, and the window-scoped mode seam).

import SwiftUI

/// Everything on a card that is not the terminal: the header (row 42), the status
/// pill (row 43) and the footer (row 47).
///
/// A plain value-driven SwiftUI view hosted in an `NSHostingView`, mirroring how
/// `CanvasHostedPanelContentView` crosses the same seam. It observes nothing: every
/// value arrives in ``model``, so this view can never be the observation boundary
/// AGENTS.md warns about near a terminal surface.
struct CarouselCardChromeView: View {
    let model: CarouselCardChromeModel

    var body: some View {
        VStack(spacing: 0) {
            CarouselCardHeaderView(model: model)
            Spacer(minLength: 0)
            CarouselCardFooterView(model: model)
        }
    }
}

/// One card's chrome, as values. Row 85: nothing here has a default that could
/// stand in for missing data - an absent branch, pull request or port renders the
/// defined empty footer rather than a plausible-looking string.
struct CarouselCardChromeModel: Equatable {
    /// Row 42.
    var name: String
    var subtitle: String
    var iconSystemName: String
    /// Row 43. Text comes from real session state; the pill is never a constant.
    var status: CarouselSessionStatus
    /// Row 47. cmux's own per-surface signals: git branch, pull-request status,
    /// listening ports. Empty entries are dropped, not padded.
    var signalChips: [String]
    /// Row 31. The handle advertises a drag and belongs to the centre card only.
    var showsDragHandle: Bool

    var iconSide: CGFloat
    var nameFontSize: CGFloat
    var subtitleFontSize: CGFloat
    var statusFontSize: CGFloat
    var chipFontSize: CGFloat
}

/// Row 42. Icon, name, dimmed subtitle, and the status pill at the trailing edge.
struct CarouselCardHeaderView: View {
    let model: CarouselCardChromeModel

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: model.iconSystemName)
                .font(.system(size: model.iconSide * 0.62))
                .frame(width: model.iconSide, height: model.iconSide)
                .foregroundStyle(.white.opacity(0.92))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.name)
                    // Row 45: system sans, never monospace, in the card chrome. The
                    // terminal surface itself is the stated exemption.
                    .font(.system(size: model.nameFontSize, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(model.subtitle)
                    .font(.system(size: model.subtitleFontSize))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            CarouselStatusPillView(status: model.status, fontSize: model.statusFontSize)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(CarouselAccessibility.cardHeader)
    }
}

/// Row 43. Coloured dot plus short status, per session. Row 126's stopped state and
/// row 117's stale state are rendered here rather than collapsed into idle, because
/// a carousel that shows a dead or five-minute-old session as live is worse than one
/// that says what it does not know.
struct CarouselStatusPillView: View {
    let status: CarouselSessionStatus
    let fontSize: CGFloat

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: fontSize))
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(.black.opacity(0.28), in: .capsule)
        .accessibilityIdentifier(CarouselAccessibility.statusPill)
        .accessibilityLabel(label)
    }

    private var dotColor: Color {
        switch status {
        case .busy: .green
        case .idle: .green.opacity(0.55)
        case .stopped: .orange
        case .stale: .yellow
        case .outOfScope: .white.opacity(0.35)
        }
    }

    private var label: String {
        switch status {
        case .busy:
            String(localized: "carousel.status.busy", defaultValue: "Working")
        case .idle:
            String(localized: "carousel.status.idle", defaultValue: "Waiting")
        case .stopped:
            String(localized: "carousel.status.stopped", defaultValue: "Agent stopped")
        case .stale:
            String(localized: "carousel.status.stale", defaultValue: "Session data stale")
        case .outOfScope:
            String(localized: "carousel.status.outOfScope", defaultValue: "Not Claude Code")
        }
    }
}

/// Row 47. `+` bottom-left, three signal chips bottom-right.
///
/// The reference's chips were agent-suggested replies. Claude Code exposes no
/// suggested-reply surface in any inventoried data source, so the row was rewritten
/// around signals cmux already tracks per surface. A surface with none of them
/// renders the defined empty footer - it does not invent chips, which row 85 forbids.
struct CarouselCardFooterView: View {
    let model: CarouselCardChromeModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: model.chipFontSize + 1, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 24, height: 24)
                .background(.white.opacity(0.06), in: .circle)
                .accessibilityHidden(true)
            Spacer(minLength: 8)
            ForEach(model.signalChips, id: \.self) { chip in
                Text(chip)
                    .font(.system(size: model.chipFontSize))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.06), in: .capsule)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
        .accessibilityIdentifier(CarouselAccessibility.cardFooter)
    }
}

/// Accessibility identifiers the H3 XCUITests address elements by. Collected in one
/// place so a test and a view can never disagree about a string literal.
enum CarouselAccessibility {
    static let root = "carousel.root"
    static let track = "carousel.track"
    static let centreCard = "carousel.card.centre"
    static let cardHeader = "carousel.card.header"
    static let cardFooter = "carousel.card.footer"
    static let statusPill = "carousel.card.statusPill"
    static let dragHandle = "carousel.card.dragHandle"
    static let emptyState = "carousel.emptyState"
    static let terminalBody = "carousel.card.terminalBody"
    /// Row 10's defined no-capture state. A test asserts this is present on a
    /// never-visited flank and gone once that session has been centred.
    static let cardPlaceholder = "carousel.card.placeholder"

    /// Per-card identity, so a test can assert *which* session is centred rather
    /// than only that something is.
    static func card(resourceId: String) -> String { "carousel.card[\(resourceId)]" }
}
