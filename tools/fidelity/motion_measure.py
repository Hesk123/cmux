#!/usr/bin/env python3
# Modified 2026-09-02 for the cmux carousel build (cmux-carousel-ui CONTRACT, harness H2).
"""H2 -- motion measurement: duration, monotonicity, overshoot, and settle.

H2 asserts WHAT MOVED AND FOR HOW LONG from a frame sequence. It is explicitly NOT
proof of frame rate: a screen capture reads 60 fps while the app drops frames the
compositor hides. CONTRACT row 112 makes H4 the sole admissible frame-rate proof and
this harness refuses to report one, so nobody can quote it as one.

Tracking method, matching VIDEO-REVIEW 2's own: per-frame luminance-gradient edge
detection over a band, then analysis of the resulting series.

  track       follow one edge across a frame sequence and report the series
  analyse     duration / monotonicity / overshoot / settle from a series
  selftest    KNOWN-ANSWER PROOF -- reproduce VIDEO-REVIEW 2.1's measured recoil
              from video/seq3/. A harness that cannot reproduce a number we already
              know must not grade a number we do not (plan 9.3).

Clock alignment (CONTRACT row 119). Timestamps in a capture are the capture's, not
the driving process's. tools/fidelity/MarkerFlash.swift paints a white screen flash
and prints the host time of its first white frame; `--marker-threshold` finds that
frame here, and t=0 is set to it. The marker is a screen flash and deliberately NOT
the keycap hint, which is itself an animation under test -- aligning on the keycap
would make row 62 assert its own input.

Tolerance: +/-15 % on durations (CONTRACT harness preamble).
"""

import argparse
import glob
import json
import os
import sys

try:
    import numpy as np
    from PIL import Image
except ImportError as exc:  # pragma: no cover
    sys.stderr.write("H2 needs numpy and Pillow: %s\n" % exc)
    raise SystemExit(2)

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from frame_diff import luma, band_profile, find_edge  # noqa: E402

DURATION_TOLERANCE = 0.15


def frame_paths(directory):
    paths = []
    for ext in ("*.jpg", "*.jpeg", "*.png"):
        paths.extend(glob.glob(os.path.join(directory, ext)))
    if not paths:
        raise SystemExit("no frames found in %s" % directory)
    return sorted(paths)


def track_edge(paths, axis, band_lo, band_hi, search_lo, search_hi, smooth=1):
    """Edge position per frame.

    axis='y' tracks a horizontal edge (a top or bottom) using a profile averaged over
    the column band [band_lo, band_hi). Averaging over a WIDE column band is what makes
    the carousel's top edge trackable at all during a switch: all cards share one top y
    per frame (VIDEO-REVIEW 2.1), so a band spanning several cards reinforces the edge
    while their differing interiors average away. A narrow band at the viewport centre
    can land in the gap between two cards mid-switch and track nothing.

    axis='x' tracks a vertical edge (a left or right) using a row band.
    """
    series = []
    for p in paths:
        lum = luma(Image.open(p))
        if axis == "y":
            prof = band_profile(lum, 1, band_lo, band_hi)
        else:
            prof = band_profile(lum, 0, band_lo, band_hi)
        try:
            series.append(find_edge(prof, search_lo, search_hi, 0, smooth))
        except ValueError:
            series.append(float("nan"))
    return series


def analyse(series, fps, settle_epsilon=1.0, settle_frames=3):
    """Duration, monotonicity and overshoot of a motion series.

    `settle_epsilon` is in the series' own units (device px). A move is settled once
    it has stayed within epsilon of its final value for `settle_frames` frames.
    """
    a = np.asarray(series, dtype=np.float64)
    ok = ~np.isnan(a)
    if ok.sum() < 4:
        raise SystemExit("too few tracked frames to analyse")
    idx = np.arange(len(a))[ok]
    vals = a[ok]

    start_val = vals[0]
    final_val = vals[-1]
    travel = final_val - start_val

    # Motion start: first frame that has moved more than epsilon from rest.
    moving = np.abs(vals - start_val) > settle_epsilon
    first = int(idx[np.argmax(moving)]) if moving.any() else int(idx[0])

    # Settle: last frame that is still outside epsilon of the final value, plus one.
    off = np.abs(vals - final_val) > settle_epsilon
    last = int(idx[len(off) - 1 - np.argmax(off[::-1])]) + 1 if off.any() else first

    duration = (last - first) / float(fps)

    # Overshoot, relative to the total travel. Zero travel (a there-and-back dip)
    # is reported by extreme instead, which is what the recoil needs.
    if abs(travel) > settle_epsilon:
        if travel > 0:
            overshoot = (float(np.max(vals)) - final_val) / abs(travel)
        else:
            overshoot = (final_val - float(np.min(vals))) / abs(travel)
        overshoot = max(0.0, overshoot)
    else:
        overshoot = 0.0

    # Monotonicity over the moving span, sign-aware and epsilon-tolerant.
    span = vals[(idx >= first) & (idx <= last)]
    steps = np.diff(span)
    if abs(travel) > settle_epsilon:
        wrong = float(np.sum(np.abs(steps[np.sign(steps) != np.sign(travel)])))
        monotonic_ratio = 1.0 - (wrong / max(1e-9, float(np.sum(np.abs(steps)))))
    else:
        monotonic_ratio = float("nan")

    return {
        "frames": int(ok.sum()),
        "fps": fps,
        "start": round(float(start_val), 3),
        "final": round(float(final_val), 3),
        "travel": round(float(travel), 3),
        "min": round(float(np.min(vals)), 3),
        "max": round(float(np.max(vals)), 3),
        "extreme_excursion": round(float(max(np.max(vals) - start_val,
                                             start_val - np.min(vals))), 3),
        "first_moving_frame": first,
        "settled_frame": last,
        "duration_s": round(duration, 4),
        "overshoot_fraction": round(overshoot, 4),
        "monotonic_ratio": None if np.isnan(monotonic_ratio) else round(monotonic_ratio, 4),
    }


def find_marker_frame(paths, threshold=200.0):
    """Index of the first frame whose mean luminance exceeds `threshold`.

    That is the marker's white flash. t = 0 for every duration in the run is this
    frame, which is how the capture's clock is tied to the driving process's.
    """
    for i, p in enumerate(paths):
        if float(luma(Image.open(p)).mean()) >= threshold:
            return i
    return None


def cmd_track(args):
    paths = frame_paths(args.frames)
    if args.marker_threshold is not None:
        m = find_marker_frame(paths, args.marker_threshold)
        if m is None:
            sys.stderr.write("CLOCK ALIGNMENT FAILED: no marker flash frame found above "
                             "mean luminance %.1f. Durations from this capture are not "
                             "comparable to the driving process's timestamps.\n"
                             % args.marker_threshold)
            return 1
        sys.stderr.write("clock aligned: marker flash at frame %d\n" % m)
        paths = paths[m + 1:]
    series = track_edge(paths, args.axis, args.band_lo, args.band_hi,
                        args.search_lo, args.search_hi, args.smooth)
    report = analyse(series, args.fps, args.settle_epsilon)
    report["series"] = [None if np.isnan(v) else round(v, 2) for v in series]
    failed = 0
    if args.expect_duration is not None:
        lo = args.expect_duration * (1 - DURATION_TOLERANCE)
        hi = args.expect_duration * (1 + DURATION_TOLERANCE)
        report["duration_expected"] = args.expect_duration
        report["duration_pass"] = bool(lo <= report["duration_s"] <= hi)
        failed += 0 if report["duration_pass"] else 1
    if args.max_overshoot is not None:
        report["overshoot_pass"] = bool(report["overshoot_fraction"] <= args.max_overshoot)
        failed += 0 if report["overshoot_pass"] else 1
    if args.min_monotonic is not None and report["monotonic_ratio"] is not None:
        report["monotonic_pass"] = bool(report["monotonic_ratio"] >= args.min_monotonic)
        failed += 0 if report["monotonic_pass"] else 1
    print(json.dumps(report, indent=2))
    print("\nH2 measures duration, monotonicity and overshoot. It does NOT measure "
          "frame rate -- CONTRACT row 112 makes H4 the only admissible proof of that.",
          file=sys.stderr)
    return 1 if failed else 0


def cmd_selftest(args):
    """KNOWN-ANSWER PROOF against VIDEO-REVIEW 2.1's measured track recoil.

    Published series, seq3/ at 60 fps over 7.05-7.65 s, card top edge in device px:
        t     7.150 7.183 7.200 7.217 7.233 7.267 7.300 7.333 7.383 7.417
        top y   295   299   306   311   314   308   302   300   296   295
    so: rest 295, peak 314, excursion 19 device px, then a return to rest.
    A 38 device px height loss on a 1334-tall card is a track scale of 0.971.
    Profile: in over ~65 ms (ease-in), out over ~185 ms (ease-out).

    Two things this proof deliberately does NOT assert.

    1. Absolute edge y. This detector places an edge at the luminance gradient's
       peak, i.e. mid-ramp; VIDEO-REVIEW read the first card-coloured pixel. That is
       a fixed ~+3.3 device px convention offset, visible identically on H1's left
       edge. Every quantity the contract actually asserts is a DIFFERENCE -- an
       excursion, a scale, a duration -- and a fixed offset cancels out of all of
       them. Asserting the absolute value would only be asserting the convention.

    2. The whole 36-frame window. seq3 spans 7.05-7.65 s and VIDEO-REVIEW 2.1 records
       presses 330 ms apart at 7.15 AND 7.48, so the window holds two recoils. The
       first is the known-answer case; the second's onset is asserted separately as
       evidence the tracker follows a re-targeted, interrupted sequence rather than
       smoothing it into one move.
    """
    paths = frame_paths(args.frames)
    if len(paths) < 30:
        sys.stderr.write("selftest expects video/seq3 (36 frames), got %d\n" % len(paths))
        return 2
    # Wide column band across several cards; the top edge is shared, interiors are not.
    series = track_edge(paths, "y", 700, 2000, 240, 420, args.smooth)
    a = np.asarray(series, dtype=np.float64)

    first_end = 26              # frames 0-25 hold the 7.15 s switch
    first = a[:first_end]
    second = a[first_end:]
    rest = float(np.nanmin(first[:6]))
    peak_idx = int(np.nanargmax(first))
    peak = float(first[peak_idx])
    excursion = peak - rest
    implied_scale = 1.0 - (2.0 * excursion / 1334.0)

    moving = np.where(first - rest > 1.0)[0]
    start_idx = int(moving[0]) if len(moving) else 0
    settled = np.where(first - rest > 1.0)[0]
    settle_idx = int(settled[-1]) + 1 if len(settled) else peak_idx
    in_s = (peak_idx - start_idx) / 60.0
    out_s = (settle_idx - peak_idx) / 60.0

    checks = [
        ("recoil.excursion_device", excursion, 19.0, 4.0),
        ("recoil.implied_track_scale", implied_scale, 0.9715, 0.006),
        ("recoil.returns_to_rest_device", abs(float(first[-1]) - rest), 0.0, 1.5),
        ("recoil.in_seconds", in_s, 0.065, 0.065 * DURATION_TOLERANCE + 1.0 / 60.0),
        ("recoil.out_seconds", out_s, 0.185, 0.185 * DURATION_TOLERANCE + 1.0 / 60.0),
        ("recoil.second_press_excursion_device",
         float(np.nanmax(second)) - rest, 19.0, 5.0),
    ]
    failed = 0
    for name, got, want, tol in checks:
        ok = abs(got - want) <= tol
        failed += 0 if ok else 1
        print("%s  %-38s %9.4f  expected %-8.4f delta %+8.4f (tol %.4f)"
              % ("PASS" if ok else "FAIL", name, got, want, got - want, tol))
    print("\nedge-convention offset vs VIDEO-REVIEW: rest measured %.2f, published 295 "
          "(+%.2f device px, mid-ramp vs first-pixel; cancels from every difference)"
          % (rest, rest - 295.0))
    print("tracked series (device px): %s"
          % [None if np.isnan(v) else round(v, 1) for v in series])
    if failed:
        print("\nH2 KNOWN-ANSWER PROOF: FAIL -- this harness must not grade anything.")
    else:
        print("\nH2 KNOWN-ANSWER PROOF: PASS -- reproduces VIDEO-REVIEW 2.1's measured "
              "track recoil (excursion, scale, in/out profile, and the 330 ms re-press) "
              "from %s. The harness may grade durations, monotonicity and overshoot. "
              "It may NOT be quoted for frame rate." % args.frames)
    return 1 if failed else 0


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--smooth", type=int, default=1)
    sub = p.add_subparsers(dest="cmd")

    t = sub.add_parser("track", help="follow one edge across a frame sequence")
    t.add_argument("frames", help="directory of extracted frames, in order")
    t.add_argument("--axis", choices=("x", "y"), required=True,
                   help="x tracks a vertical edge (left/right); y a horizontal one (top/bottom)")
    t.add_argument("--band-lo", type=float, required=True)
    t.add_argument("--band-hi", type=float, required=True)
    t.add_argument("--search-lo", type=float, required=True)
    t.add_argument("--search-hi", type=float, required=True)
    t.add_argument("--fps", type=float, default=60.0)
    t.add_argument("--settle-epsilon", type=float, default=1.0)
    t.add_argument("--marker-threshold", type=float, default=None,
                   help="mean luminance identifying the marker flash; enables clock alignment")
    t.add_argument("--expect-duration", type=float, default=None, help="seconds, +/-15%%")
    t.add_argument("--max-overshoot", type=float, default=None, help="fraction of travel")
    t.add_argument("--min-monotonic", type=float, default=None, help="0-1")
    t.set_defaults(func=cmd_track)

    s = sub.add_parser("selftest", help="known-answer proof against video/seq3")
    s.add_argument("frames", help="path to video/seq3")
    s.set_defaults(func=cmd_selftest)

    args = p.parse_args(argv)
    if not getattr(args, "func", None):
        p.print_help()
        return 2
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
