// Modified 2026-09-02 for the cmux carousel build (cmux-carousel-ui CONTRACT row 119).
//
// The capture precondition. CONTRACT row 119 requires that before ANY H1 or H2
// measurement runs, three facts are asserted and the run ABORTS LOUDLY if any fails:
//
//   1. NSScreen.main.backingScaleFactor == 2.0
//   2. visibleFrame >= 1344 x 1080 logical
//   3. the app window is 1344 x 1080 logical, backing to 2688 x 2160
//
// The reason the row exists: without a hard precondition, roughly twenty-five
// absolute-pixel rows quietly become "n/a on this hardware" the moment the display
// is in the wrong mode, and a fidelity report full of silent exemptions reads like
// a pass. Aborting is the point.
//
// All three are asserted HERE. Checks 1 and 2 are display facts. Check 3 is the
// window's own frame, read from CGWindowListCopyWindowInfo, and leaving it to "the
// capture step" was a real hole: the Phase 0 spike ran its CALayer test on a window
// macOS had SILENTLY CLAMPED to 1670 x 1033, because the display was not in More
// Space. Nothing failed. The numbers looked valid and were not. A display assertion
// alone cannot catch that -- only the window's actual size can.
//
// kCGWindowBounds is readable WITHOUT the Screen Recording grant; only window IMAGES
// need it. So this check works from an ssh session, which is where the harness runs.
//
// Build: swiftc -O -parse-as-library -o display-precondition DisplayPrecondition.swift
// Run:   ./display-precondition            # asserts, exit 0 or 1
//        ./display-precondition --report   # prints state, always exit 0
//        ./display-precondition --window "cmux DEV"   # also assert the WINDOW frame

import AppKit

struct DisplayFacts {
    let backingScaleFactor: Double
    let frameWidth: Double
    let frameHeight: Double
    let visibleWidth: Double
    let visibleHeight: Double
    let refreshRate: Double
    let localizedName: String
}

@MainActor
func readMainScreen() -> DisplayFacts? {
    guard let screen = NSScreen.main else { return nil }
    return DisplayFacts(backingScaleFactor: Double(screen.backingScaleFactor),
                        frameWidth: Double(screen.frame.width),
                        frameHeight: Double(screen.frame.height),
                        visibleWidth: Double(screen.visibleFrame.width),
                        visibleHeight: Double(screen.visibleFrame.height),
                        refreshRate: screen.maximumFramesPerSecond > 0
                            ? Double(screen.maximumFramesPerSecond) : 0,
                        localizedName: screen.localizedName)
}

/// The on-screen bounds of the frontmost window whose owner name contains `match`.
///
/// Uses the window list rather than the accessibility API because window BOUNDS are
/// permission-free, while driving another app through accessibility is not.
func windowBounds(ownerMatching match: String) -> (owner: String, width: Double, height: Double)? {
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
        return nil
    }
    for entry in raw {
        guard let owner = entry[kCGWindowOwnerName as String] as? String,
              owner.localizedCaseInsensitiveContains(match),
              let boundsDict = entry[kCGWindowBounds as String] as? [String: Any],
              let width = boundsDict["Width"] as? Double,
              let height = boundsDict["Height"] as? Double else { continue }
        // Skip menu-bar-sized slivers and other chrome windows the app also owns.
        if width < 200 || height < 200 { continue }
        return (owner, width, height)
    }
    return nil
}

@main
struct DisplayPreconditionMain {
    static let requiredBackingScale = 2.0
    static let requiredWidth = 1344.0
    static let requiredHeight = 1080.0

    @MainActor
    static func main() {
        let args = CommandLine.arguments
        let reportOnly = args.contains("--report")
        // --window <owner-substring> adds check 3: the window's own frame.
        var windowMatch: String?
        if let i = args.firstIndex(of: "--window"), i + 1 < args.count {
            windowMatch = args[i + 1]
        }
        guard let facts = readMainScreen() else {
            FileHandle.standardError.write(Data("PRECONDITION ABORT: no main screen\n".utf8))
            exit(reportOnly ? 0 : 1)
        }

        let json: [String: Any] = [
            "screen": facts.localizedName,
            "backing_scale_factor": facts.backingScaleFactor,
            "frame": ["width": facts.frameWidth, "height": facts.frameHeight],
            "visible_frame": ["width": facts.visibleWidth, "height": facts.visibleHeight],
            "max_fps": facts.refreshRate,
            "required": ["backing_scale_factor": requiredBackingScale,
                         "visible_width": requiredWidth,
                         "visible_height": requiredHeight],
        ]
        if let data = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys, .prettyPrinted]),
           let text = String(data: data, encoding: .utf8) {
            print(text)
        }

        if reportOnly { exit(0) }

        var failures: [String] = []
        if abs(facts.backingScaleFactor - requiredBackingScale) > 0.0001 {
            failures.append("backingScaleFactor is \(facts.backingScaleFactor), required \(requiredBackingScale). "
                            + "Absolute-pixel rows convert device px to CSS px by dividing by this number; "
                            + "at 1.0 every one of them is off by a factor of two.")
        }
        if facts.visibleWidth < requiredWidth || facts.visibleHeight < requiredHeight {
            failures.append("visibleFrame is \(facts.visibleWidth) x \(facts.visibleHeight), "
                            + "required at least \(requiredWidth) x \(requiredHeight). "
                            + "The fidelity window cannot be opened at its asserted size on this mode.")
        }

        // Check 3. The window, not the display. This is the one the spike needed.
        if let match = windowMatch {
            if let win = windowBounds(ownerMatching: match) {
                print("window owner \"\(win.owner)\": \(win.width) x \(win.height) logical")
                if abs(win.width - requiredWidth) > 0.5 || abs(win.height - requiredHeight) > 0.5 {
                    failures.append("the window is \(win.width) x \(win.height), required exactly "
                                    + "\(requiredWidth) x \(requiredHeight). macOS CLAMPS a window that "
                                    + "does not fit the current mode and reports no error, so a "
                                    + "measurement taken now would look valid and be wrong -- the Phase 0 "
                                    + "spike lost a run to exactly this at 1670 x 1033.")
                }
            } else {
                failures.append("no on-screen window found whose owner name contains \"\(match)\". "
                                + "Launch the tagged app first; a measurement with no window is not a "
                                + "measurement.")
            }
        }

        if failures.isEmpty {
            print("PRECONDITION PASS: \(facts.localizedName) at "
                  + "\(facts.frameWidth)x\(facts.frameHeight) logical, "
                  + "backing scale \(facts.backingScaleFactor), "
                  + "visibleFrame \(facts.visibleWidth)x\(facts.visibleHeight), "
                  + "\(Int(facts.refreshRate)) Hz.")
            exit(0)
        }
        FileHandle.standardError.write(Data("PRECONDITION ABORT\n".utf8))
        for f in failures {
            FileHandle.standardError.write(Data("  - \(f)\n".utf8))
        }
        FileHandle.standardError.write(Data(
            "Set the fidelity display mode first: tools/fidelity/fidelity-display.sh set\n".utf8))
        exit(1)
    }
}
