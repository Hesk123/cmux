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
// This program owns checks 1 and 2, which are display facts and can be asserted
// before the app is even launched. Check 3 is a property of the window and is
// asserted by the capture step, which reads pointPixelScale back from
// SCStreamConfiguration's contentInfo (row 119's wording).
//
// Build: swiftc -O -parse-as-library -o display-precondition DisplayPrecondition.swift
// Run:   ./display-precondition            # asserts, exit 0 or 1
//        ./display-precondition --report   # prints state, always exit 0

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

@main
struct DisplayPreconditionMain {
    static let requiredBackingScale = 2.0
    static let requiredWidth = 1344.0
    static let requiredHeight = 1080.0

    @MainActor
    static func main() {
        let reportOnly = CommandLine.arguments.contains("--report")
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
