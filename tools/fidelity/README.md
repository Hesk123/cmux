# Fidelity harness — entry points for every unit

Modified 2026-09-02 for the cmux carousel build (cmux-carousel-ui CONTRACT, harness H1–H4).

This is what U1–U6 call. Nothing here changes app behaviour; it measures it.

## The four instruments, and what each may be quoted for

| | Proves | Does NOT prove | Entry point |
|---|---|---|---|
| **H1** | static geometry, scale, corner radius, colour | anything about motion | `frame_diff.py` |
| **H2** | duration, monotonicity, overshoot | **frame rate** — a capture reads 60 fps while the app drops frames the compositor hides | `motion_measure.py` |
| **H3** | element existence, geometry and data binding, in process | rendering quality | `make_fixture_root.py` + XCUITest |
| **H4** | sustained frame rate and hitching | geometry | `instrument_h4.sh` |

Row 112 makes H4 the **sole** admissible frame-rate proof. `motion_measure.py` refuses to
report one so it cannot be quoted as one by accident.

## Before any H1 or H2 measurement — the row-119 precondition

```
tools/fidelity/fidelity-display.sh set      # More Space mode, 1920x1243 logical @2x
tools/fidelity/fidelity-display.sh check    # aborts non-zero if the mode is wrong
# ... measure ...
tools/fidelity/fidelity-display.sh restore  # back to the machine's default mode
```

`check` **aborts** rather than warning. Without it, roughly twenty-five absolute-pixel
rows quietly become "n/a on this hardware" and a report full of silent exemptions
reads like a pass. The default mode's `visibleFrame` is 1710 × 1073 — **seven logical
pixels short** of the 1080 the fidelity window needs, which is the entire reason the
mode has to be switched. This machine is a 60 Hz panel with no ProMotion.

Restore the mode when you are done. It is Dawid's daily driver.

## Known-answer proofs — run these before trusting either harness

```
python3 tools/fidelity/frame_diff.py    selftest <ref>/hi/rest.png
python3 tools/fidelity/motion_measure.py selftest <ref>/seq3
```

Both reproduce VIDEO-REVIEW's own published measurements. A harness that cannot
reproduce a number we already know must not grade a number we do not.

**One correction they surfaced.** VIDEO-REVIEW 1.2 reports the card's corner radius as
"~53 device / 26 CSS", read as the settle point of the corner walk. A least-squares
circular fit over all 60 arc rows gives **62.75 device (31.4 CSS) at 0.48 px RMS**, and
VIDEO-REVIEW's own first data point (x 542 at y 299) agrees with the fit, not with 53.
A settle read is a floor on a radius, never the radius. **U1 should use ~31 CSS and a
circular `RoundedRectangle`, not `.continuous`** — the three-parameter fit put the
superellipse exponent at 1.90, so the corner is circular.

## Clock alignment (row 119)

H2 durations are meaningless against a driving process's timestamps unless something
visible ties the two clocks together.

```
swiftc -O -parse-as-library -o /tmp/marker-flash tools/fidelity/MarkerFlash.swift
/tmp/marker-flash --flash-frames 3 --sweep-seconds 1.5     # prints the flash host time
python3 tools/fidelity/motion_measure.py track <frames> --marker-threshold 200 ...
```

The marker is a **screen flash and deliberately not the keycap hint**. The keycap is an
animation under test; aligning on it would make row 62 assert its own input.

## H3 fixtures

```
python3 tools/fidelity/make_fixture_root.py /tmp/fx --preset three
export CMUX_CAROUSEL_DATA_ROOT=/tmp/fx
```

Presets cover row 116's `zero` / `one` / `two`, plus `three`, `forty`,
`out-of-scope` (row 124) and `unmounted` (row 132).

**Assert the canary NAME, never a count.** Every fixture writes session names prefixed
`CANARY-FIXTURE-`, which cannot occur in the real Hive root. A count-only assertion
passes when the fixture failed to bite and the UI is showing the real sessions instead.

**The negative control is mandatory**, not optional:

```
python3 tools/fidelity/make_fixture_root.py /tmp/fx-empty --empty
```

Assert both that the empty state renders **and** that no real session name appears. A
provider that silently falls back to the real root passes every positive control and
fails nothing without this.

## Gotchas that cost real time here

- `ssh mac '<cmd>'` does not source the profile, so Homebrew is off `PATH`. Export
  `/opt/homebrew/bin` or use `zsh -lc`.
- `xcrun --show-sdk-path` without `--sdk macosx` resolves to the **Command Line Tools**
  SDK (Swift 6.4), which the Xcode-beta compiler (6.3) refuses to build against. Set
  `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer` and pass `--sdk macosx`.
- `MarkerFlash.swift` and `DisplayPrecondition.swift` need `-parse-as-library`; `@main`
  is rejected in a module that also has top-level code.
- The `avfoundation` screen-capture device index on this machine is **3**
  ("Capture screen 0"). Machine-specific; re-list rather than assume it elsewhere.
- ffmpeg screen capture needs the Screen Recording TCC grant, which an ssh session does
  not have — see row 122 in MAKER-U7.md. H1 and the flank snapshots do **not** need it.
