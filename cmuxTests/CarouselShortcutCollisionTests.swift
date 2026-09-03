// GPL-3.0-or-later modified-file notice (CONTRACT row 129):
// Modified 2026-09-02 for the cmux carousel UI (unit U3, prompt bar / focus / pty routing).

import AppKit
import CmuxSettings
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// CONTRACT row 114: "A test asserts the build registers no chord already bound
/// by cmux, **enumerated from that binding table rather than from memory**."
///
/// Enumeration is the whole point. A hand-written list of "chords we think are
/// taken" would go stale the first time upstream adds a shortcut, and this repo
/// carries roughly three thousand open pull requests.
@MainActor
@Suite("Carousel shortcut collisions")
struct CarouselShortcutCollisionTests {
    private static let carouselActions: [KeyboardShortcutSettings.Action] = [
        .toggleCarouselLayout,
        .carouselNavigatePrevious,
        .carouselNavigateNext,
        .carouselToggleGrid,
    ]

    /// Two default bindings collide when both are bound and every field of the
    /// keystroke matches.
    private static func collides(
        _ lhs: StoredShortcut,
        _ rhs: StoredShortcut
    ) -> Bool {
        guard !lhs.isUnbound, !rhs.isUnbound else { return false }
        return lhs.key.lowercased() == rhs.key.lowercased()
            && lhs.command == rhs.command
            && lhs.shift == rhs.shift
            && lhs.option == rhs.option
            && lhs.control == rhs.control
    }

    @Test("No carousel chord collides with any other cmux default binding")
    func carouselChordsAreFreeAcrossTheWholeTable() {
        let allActions = KeyboardShortcutSettings.Action.allCases
        #expect(allActions.count > 100, "the binding table must actually be enumerable")

        for carouselAction in Self.carouselActions {
            let carouselShortcut = carouselAction.defaultShortcut
            #expect(!carouselShortcut.isUnbound, "\(carouselAction.rawValue) must be bound")

            for other in allActions where !Self.carouselActions.contains(other) {
                #expect(
                    !Self.collides(carouselShortcut, other.defaultShortcut),
                    """
                    \(carouselAction.rawValue) (\(carouselShortcut.key)) collides with \
                    \(other.rawValue). Pick another chord; do not steal an existing binding.
                    """
                )
            }
        }
    }

    @Test("The four carousel chords do not collide with one another")
    func carouselChordsAreMutuallyDistinct() {
        for (index, lhs) in Self.carouselActions.enumerated() {
            for rhs in Self.carouselActions.dropFirst(index + 1) {
                #expect(
                    !Self.collides(lhs.defaultShortcut, rhs.defaultShortcut),
                    "\(lhs.rawValue) and \(rhs.rawValue) share a chord"
                )
            }
        }
    }

    /// Negative control, mandatory. Without it this suite would pass green even
    /// if `collides` always returned false, or `allCases` came back empty — the
    /// exact vacuous shape CONTRACT row 134 exists to catch. Ctrl+Cmd+G is
    /// taken by `newWorkspaceGroup`, which is why the grid chord is Ctrl+Cmd+M.
    @Test("The collision detector detects a real collision")
    func detectorCatchesAKnownTakenChord() {
        let controlCommandG = StoredShortcut(
            key: "g", command: true, shift: false, option: false, control: true
        )

        let colliding = KeyboardShortcutSettings.Action.allCases.filter {
            Self.collides(controlCommandG, $0.defaultShortcut)
        }

        #expect(
            colliding.contains(.newWorkspaceGroup),
            """
            Ctrl+Cmd+G must still report as taken by newWorkspaceGroup. If it no \
            longer does, either the detector stopped detecting or the upstream \
            table moved — check before trusting the positive cases above.
            """
        )
    }

    /// Ruling D-15 justified Ctrl+Cmd+arrows partly on a claim about the table.
    /// The claim as written in the contract is wrong — Cmd+Option+arrows ARE
    /// bound — so this test pins what is actually true and load-bearing: the
    /// *Ctrl+Cmd* arrow chords are free.
    @Test("Cmd+Option arrows are bound, and Ctrl+Cmd arrows are not")
    func arrowChordFactsMatchTheTable() {
        #expect(
            KeyboardShortcutSettings.Action.focusLeft.defaultShortcut.option,
            "focusLeft is Cmd+Option+Left; the contract's 'no arrow is bound' line is inaccurate"
        )

        let controlCommandLeft = StoredShortcut(
            key: "\u{2190}", command: true, shift: false, option: false, control: true
        )
        let takenByOthers = KeyboardShortcutSettings.Action.allCases
            .filter { !Self.carouselActions.contains($0) }
            .filter { Self.collides(controlCommandLeft, $0.defaultShortcut) }

        #expect(takenByOthers.isEmpty, "Ctrl+Cmd+Left is claimed by \(takenByOthers)")
    }

    /// H1: the four actions exist in the Settings table with the same chords,
    /// so the shortcut editor, rebinding and conflict detector can see them.
    /// Without this, a user rebinding Ctrl+Cmd+M in Settings is told there is
    /// no conflict while silently shadowing the grid chord.
    @Test("The Settings table mirrors the app table for all four actions")
    func settingsTableMirrorsTheAppTable() {
        let pairs: [(KeyboardShortcutSettings.Action, ShortcutAction)] = [
            (.toggleCarouselLayout, .toggleCarouselLayout),
            (.carouselNavigatePrevious, .carouselNavigatePrevious),
            (.carouselNavigateNext, .carouselNavigateNext),
            (.carouselToggleGrid, .carouselToggleGrid),
        ]
        for (app, settings) in pairs {
            let a = app.defaultShortcut
            guard let d = settings.defaultShortcut else {
                Issue.record("\(settings) has no default in the Settings table")
                continue
            }
            #expect(
                a.key.lowercased() == d.key.lowercased()
                    && a.command == d.command && a.shift == d.shift
                    && a.option == d.option && a.control == d.control,
                "\(settings) default \(d.key) does not match the app table")
        }
    }

    /// Row 114's fallback set: grid and mode move, navigation stays, and every
    /// fallback chord is free in both tables.
    @Test("The fallback chords differ where they must and are free in both tables")
    func fallbackChordsAreFree() {
        let fallback = CarouselShortcutBindings.fallback
        let primary = CarouselShortcutBindings.contractDefaults
        #expect(fallback.navigatePrevious == primary.navigatePrevious)
        #expect(fallback.navigateNext == primary.navigateNext)
        #expect(fallback.toggleGrid != primary.toggleGrid)
        #expect(fallback.toggleCarouselMode != primary.toggleCarouselMode)

        for stroke in [fallback.toggleGrid, fallback.toggleCarouselMode] {
            for other in KeyboardShortcutSettings.Action.allCases
                where !Self.carouselActions.contains(other)
            {
                #expect(
                    !Self.collides(stroke, other.defaultShortcut),
                    "fallback chord \(stroke.key) collides with \(other.rawValue)")
            }
            for other in ShortcutAction.allCases {
                guard let d = other.defaultShortcut else { continue }
                #expect(
                    !(stroke.key.lowercased() == d.key.lowercased()
                        && stroke.command == d.command && stroke.shift == d.shift
                        && stroke.option == d.option && stroke.control == d.control),
                    "fallback chord \(stroke.key) collides with Settings \(other)")
            }
        }
    }
}
