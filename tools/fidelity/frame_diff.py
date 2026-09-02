#!/usr/bin/env python3
# Modified 2026-09-02 for the cmux carousel build (cmux-carousel-ui CONTRACT, harness H1).
"""H1 -- static fidelity: geometry, scale, radius and colour from a single frame.

Reproduces VIDEO-REVIEW.md's own methods: luminance-gradient edge detection along a
scanline, corner-radius fitting from per-row left edges, and direct colour sampling.

Every measurement is reported in BOTH device px and CSS px. Device px are the pixels
in the image; CSS px are device / backing_scale. The reference capture is 2x, and so
is the build's fidelity capture (CONTRACT row 119), so backing_scale defaults to 2.

Normalization (CONTRACT harness preamble): a CSS target is a ratio of window width
anchored to the reference's 1344-wide logical viewport. `--window-width` states the
window this frame was captured at; ratios are computed against it, and `--expect-*`
targets given at W=1344 are rescaled by W/1344 before comparison.

Tolerances (CONTRACT harness preamble): geometry +/-2 CSS px, scale +/-0.005,
colour +/-6 per channel, unless a row overrides them.

Subcommands
-----------
  card        measure one card's box, radius, and edge profile
  scale       measure a flank card's scale against the centre card
  color       sample a colour patch and compare against an expected hex
  selftest    KNOWN-ANSWER PROOF -- reproduce VIDEO-REVIEW's published numbers from
              the reference frame. A harness that cannot reproduce a number we
              already know must not grade a number we do not (plan 9.3).

Exit status is 0 only when every assertion made in the run passed.
"""

import argparse
import json
import sys

try:
    import numpy as np
    from PIL import Image
except ImportError as exc:  # pragma: no cover - environment problem, not a measurement
    sys.stderr.write("H1 needs numpy and Pillow: %s\n" % exc)
    raise SystemExit(2)

REFERENCE_VIEWPORT_CSS = 1344.0

# Tolerances, in CSS px / scale units / per-channel 0-255.
TOL_GEOMETRY_CSS = 2.0
TOL_SCALE = 0.005
TOL_COLOR = 6


def luma(img):
    """Rec.601 luminance as a float array, shape (h, w)."""
    a = np.asarray(img.convert("RGB"), dtype=np.float64)
    return 0.299 * a[:, :, 0] + 0.587 * a[:, :, 1] + 0.114 * a[:, :, 2]


def _smooth(profile, radius):
    if radius <= 0:
        return profile
    k = np.ones(2 * radius + 1) / (2 * radius + 1)
    return np.convolve(profile, k, mode="same")


def find_edge(profile, start, stop, direction, smooth=1):
    """Index of the strongest luminance gradient in [start, stop).

    `direction` is +1 to look for a rising edge (entering a brighter region as the
    index grows) and -1 for a falling one; 0 takes the largest magnitude either way.
    Returns a sub-pixel index by parabolic interpolation around the peak, which is
    what makes a +/-2 CSS px (= 4 device px) tolerance meaningful at all.
    """
    start = max(int(start), 1)
    stop = min(int(stop), len(profile) - 1)
    if stop - start < 3:
        raise ValueError("edge search window too small: [%d, %d)" % (start, stop))
    grad = np.diff(_smooth(np.asarray(profile, dtype=np.float64), smooth))
    window = grad[start:stop]
    if direction > 0:
        scored = window
    elif direction < 0:
        scored = -window
    else:
        scored = np.abs(window)
    i = int(np.argmax(scored))
    peak = start + i
    # Parabolic refinement across the three samples around the peak.
    if 0 < i < len(scored) - 1:
        y0, y1, y2 = scored[i - 1], scored[i], scored[i + 1]
        denom = y0 - 2.0 * y1 + y2
        if abs(denom) > 1e-9:
            peak = peak + 0.5 * (y0 - y2) / denom
    # diff() index j sits between samples j and j+1, so the edge is at j + 0.5.
    return float(peak) + 0.5


def band_profile(lum, axis, lo, hi):
    """Mean luminance profile across a band of rows (axis=0) or columns (axis=1).

    Averaging over a band is what separates a card edge from the text inside it.
    A glyph edge is steep but only a few rows tall, so it averages away; the card's
    edge runs the full height of the band and survives. A single scanline cannot
    tell the two apart, and picks whichever happens to be steeper.
    """
    lo = max(int(lo), 0)
    hi = min(int(hi), lum.shape[axis])
    if hi - lo < 2:
        raise ValueError("band too thin: [%d, %d)" % (lo, hi))
    if axis == 0:
        return lum[lo:hi, :].mean(axis=0)
    return lum[:, lo:hi].mean(axis=1)


def measure_card(lum, cx, cy, half_w, half_h, smooth=1, band=0.45, inset=14, strip=70):
    """Box of the card whose interior contains (cx, cy), in two passes.

    Pass 1 finds the vertical edges from a wide band of rows: the card's left and
    right edges run the full height of the band, and text inside averages away.

    Pass 2 finds the horizontal edges from two narrow strips of columns taken just
    INSIDE the vertical edges found in pass 1. That matters. The card's bottom edge
    is a ~12-luma step (VIDEO-REVIEW 1.2: interior 18, hairline 43, wallpaper 30),
    far weaker than a message bubble or an embedded image inside the card. Sampling
    only the card's own quiet margins removes every interior element from the
    profile, so the weak real edge is the strongest thing left in the window.

    The search window must be wider and taller than the card, or the true edge lies
    outside it and the strongest interior gradient wins by default.
    """
    bh = max(4.0, half_h * band)
    bw = max(4.0, half_w * band)
    prof_x = band_profile(lum, 0, cy - bh, cy + bh)
    left = find_edge(prof_x, cx - half_w, cx - bw, 0, smooth)
    right = find_edge(prof_x, cx + bw, cx + half_w, 0, smooth)

    strip = min(strip, max(4.0, (right - left) / 6.0))
    lo_l, hi_l = left + inset, left + inset + strip
    lo_r, hi_r = right - inset - strip, right - inset
    prof_y = (band_profile(lum, 1, lo_l, hi_l) + band_profile(lum, 1, lo_r, hi_r)) / 2.0
    top = find_edge(prof_y, cy - half_h, cy - bh, 0, smooth)
    bottom = find_edge(prof_y, cy + bh, cy + half_h, 0, smooth)
    return {"left": left, "right": right, "top": top, "bottom": bottom,
            "width": right - left, "height": bottom - top,
            "center_x": (left + right) / 2.0, "center_y": (top + bottom) / 2.0}


def measure_radius(lum, box, rows=110, smooth=1, report=None):
    """Corner radius by fitting a circular arc to the top-left corner's left edge.

    For a rounded rectangle of radius r, the left edge at dy rows below the top is
        dx(dy) = r - sqrt(r^2 - (r - dy)^2)   for 0 <= dy <= r,  else 0
    so r is recovered by least squares over the measured (dy, dx) points. This is a
    fit to the whole arc, not a threshold on where the edge "looks settled" -- a
    threshold is a free parameter that can be tuned until it reproduces whatever
    number was expected, which would make the known-answer proof circular.
    """
    top = int(round(box["top"]))
    left_straight = box["left"]
    dys, dxs = [], []
    # A convex corner arc's left edge moves monotonically toward the straight side,
    # so each row is searched only between the straight edge and the previous row's
    # edge. Without that constraint a bright interior element further right can beat
    # the real edge once the arc has flattened and the edge stops being the steepest
    # thing in a wide window.
    prev = left_straight + 190.0
    settled = 0
    for dy in range(1, rows + 1):
        y = top + dy
        if y >= lum.shape[0]:
            break
        try:
            edge = find_edge(lum[y, :], left_straight - 8, prev + 10, 0, smooth)
        except ValueError:
            break
        dx = edge - left_straight
        if dx < -4.0:
            break
        dx = max(0.0, dx)
        dys.append(float(dy))
        dxs.append(dx)
        prev = max(left_straight, edge)
        settled = settled + 1 if dx < 0.8 else 0
        if settled >= 6:
            break
    if len(dys) < 12:
        return float("nan")
    dys = np.asarray(dys)
    dxs = np.asarray(dxs)
    best_r, best_sse = float("nan"), None
    for r in np.arange(8.0, 140.0, 0.25):
        inside = dys <= r
        pred = np.zeros_like(dys)
        d = r - dys[inside]
        pred[inside] = r - np.sqrt(np.maximum(0.0, r * r - d * d))
        sse = float(np.sum((pred - dxs) ** 2))
        if best_sse is None or sse < best_sse:
            best_sse, best_r = sse, float(r)
    if report is not None:
        report["radius_fit_rms_device"] = round((best_sse / len(dys)) ** 0.5, 3)
        report["radius_fit_points"] = len(dys)
    return best_r


def sample_color(img, x, y, box_size=9):
    a = np.asarray(img.convert("RGB"), dtype=np.float64)
    h = box_size // 2
    patch = a[max(0, y - h):y + h + 1, max(0, x - h):x + h + 1, :]
    mean = patch.reshape(-1, 3).mean(axis=0)
    return [int(round(v)) for v in mean]


def hex_to_rgb(s):
    s = s.lstrip("#")
    return [int(s[i:i + 2], 16) for i in (0, 2, 4)]


class Report(object):
    """Collects assertions so the process exit status means something."""

    def __init__(self, backing_scale, window_width_css):
        self.backing = float(backing_scale)
        self.window = float(window_width_css)
        self.rows = []
        self.failed = 0

    def css(self, device_value):
        return device_value / self.backing

    def ratio(self, css_value):
        return css_value / self.window

    def check(self, name, measured_css, expected_css_at_1344, tol=TOL_GEOMETRY_CSS,
              unit="CSS px", scale_with_window=True):
        expected = expected_css_at_1344
        if scale_with_window and expected is not None:
            expected = expected_css_at_1344 * self.window / REFERENCE_VIEWPORT_CSS
        ok = True
        delta = None
        if expected is not None:
            delta = measured_css - expected
            ok = abs(delta) <= tol
            if not ok:
                self.failed += 1
        self.rows.append({"name": name, "measured": round(measured_css, 3),
                          "expected": None if expected is None else round(expected, 3),
                          "delta": None if delta is None else round(delta, 3),
                          "tolerance": tol, "unit": unit, "pass": ok})
        return ok

    def emit(self, as_json):
        if as_json:
            print(json.dumps({"window_width_css": self.window,
                              "backing_scale": self.backing,
                              "checks": self.rows,
                              "failed": self.failed}, indent=2))
        else:
            width = max(len(r["name"]) for r in self.rows) if self.rows else 4
            for r in self.rows:
                verdict = "    " if r["expected"] is None else ("PASS" if r["pass"] else "FAIL")
                exp = "" if r["expected"] is None else "  expected %-9s delta %+7.3f (tol %s)" % (
                    r["expected"], r["delta"], r["tolerance"])
                print("%s  %-*s %10.3f %s%s" % (verdict, width, r["name"],
                                                r["measured"], r["unit"], exp))
        return 1 if self.failed else 0


def cmd_card(args):
    img = Image.open(args.image)
    lum = luma(img)
    box = measure_card(lum, args.cx, args.cy, args.half_width, args.half_height, args.smooth)
    rep = Report(args.backing_scale, args.window_width)
    rep.check("card.width", rep.css(box["width"]), args.expect_width)
    rep.check("card.height", rep.css(box["height"]), args.expect_height)
    rep.check("card.center_x", rep.css(box["center_x"]), args.expect_center_x)
    rep.check("card.center_y", rep.css(box["center_y"]), args.expect_center_y)
    if args.expect_radius is not None or args.radius:
        rep.check("card.radius", rep.css(measure_radius(lum, box, smooth=args.smooth)),
                  args.expect_radius)
    rep.rows.append({"name": "card.width_ratio_of_W", "measured": round(rep.ratio(rep.css(box["width"])), 4),
                     "expected": None, "delta": None, "tolerance": "-", "unit": "ratio", "pass": True})
    return rep.emit(args.json)


def cmd_scale(args):
    img = Image.open(args.image)
    lum = luma(img)
    centre = measure_card(lum, args.cx, args.cy, args.half_width, args.half_height, args.smooth)
    flank = measure_card(lum, args.flank_cx, args.cy, args.half_width, args.half_height, args.smooth)
    rep = Report(args.backing_scale, args.window_width)
    measured = flank["height"] / centre["height"]
    rep.check("flank.scale", measured, args.expect_scale, tol=TOL_SCALE,
              unit="ratio", scale_with_window=False)
    rep.rows.append({"name": "centre.height_device", "measured": round(centre["height"], 2),
                     "expected": None, "delta": None, "tolerance": "-", "unit": "device px", "pass": True})
    rep.rows.append({"name": "flank.height_device", "measured": round(flank["height"], 2),
                     "expected": None, "delta": None, "tolerance": "-", "unit": "device px", "pass": True})
    return rep.emit(args.json)


def cmd_color(args):
    img = Image.open(args.image)
    got = sample_color(img, args.x, args.y, args.box)
    rep = Report(args.backing_scale, args.window_width)
    if args.expect:
        want = hex_to_rgb(args.expect)
        for i, ch in enumerate("RGB"):
            rep.check("color.%s" % ch, got[i], want[i], tol=TOL_COLOR,
                      unit="0-255", scale_with_window=False)
    else:
        rep.rows.append({"name": "color.rgb", "measured": 0, "expected": None, "delta": None,
                         "tolerance": "-", "unit": "#%02x%02x%02x" % tuple(got), "pass": True})
    return rep.emit(args.json)


def cmd_selftest(args):
    """KNOWN-ANSWER PROOF against VIDEO-REVIEW 1.1-1.3, measured from hi/rest.png.

    Published numbers this must reproduce (device px, 2688x2160 capture):
        centre card box   x 495 -> 2192, y 298 -> 1632
        centre card size  1697 x 1334   (= 848 x 667 CSS)
        centre card cx    1343.5        (viewport centre 1344)
        corner radius     ~53 device    (~26 CSS)
        flank scale       1253/1334 = 0.9393 -> 0.94
        corner radius     ~53 device -- SUPERSEDED, see the correction note below;
                          the fitted value is 62.75 device / 31.4 CSS
    """
    img = Image.open(args.reference)
    if img.size != (2688, 2160):
        sys.stderr.write("selftest expects the 2688x2160 reference frame, got %s\n" % (img.size,))
        return 2
    lum = luma(img)
    rep = Report(2.0, REFERENCE_VIEWPORT_CSS)

    centre = measure_card(lum, 1344, 965, 900, 760, args.smooth)
    rep.check("ref.centre.width", rep.css(centre["width"]), 848.0)
    rep.check("ref.centre.height", rep.css(centre["height"]), 667.0)
    rep.check("ref.centre.center_x", rep.css(centre["center_x"]), 671.75)
    rep.check("ref.centre.center_y", rep.css(centre["center_y"]), 482.5)
    rep.check("ref.centre.left", rep.css(centre["left"]), 247.5)
    rep.check("ref.centre.right", rep.css(centre["right"]), 1096.0)
    rep.check("ref.centre.top", rep.css(centre["top"]), 149.0)
    rep.check("ref.centre.bottom", rep.css(centre["bottom"]), 816.0)
    # CORRECTION to VIDEO-REVIEW 1.2, found by this harness and recorded rather than
    # tuned away. VIDEO-REVIEW reports "radius ~= 53 device / 26 CSS", read as the
    # settle point: the row at which the left edge stops moving (~y 350 minus top
    # ~297). For a circular arc the settle point equals the radius in theory, but the
    # last ~15 % of an arc is sub-pixel and reads as already straight, so a settle
    # read is a FLOOR on the radius, never the radius.
    #
    # A least-squares circular fit over all 60 arc rows gives r = 62.75 device
    # (31.4 CSS) at 0.48 device px RMS, and a three-parameter fit that also frees the
    # exponent and the straight-side x gives r = 60.0, n = 1.90, RMS 0.446 -- i.e. the
    # corner is circular, not a continuous/squircle corner, and r is 60-63 device.
    #
    # VIDEO-REVIEW's own data contradicts its 53. It records y 299 -> x 542, i.e.
    # dx = 47 at dy ~= 1.5. A circle of r = 53 predicts dx = 53 - sqrt(3r - 2.25)
    # = 40.5 there; r = 62.75 predicts 49.1. The measured 47 sits with the fit.
    #
    # Consequence for the build: the card's corner radius is ~31 CSS px, not 26, and
    # U1 should use a circular RoundedRectangle rather than .continuous.
    fitinfo = {}
    rep.check("ref.centre.radius", rep.css(measure_radius(lum, centre, smooth=args.smooth,
                                                          report=fitinfo)), 31.4, tol=2.0)
    rep.rows.append({"name": "ref.centre.radius_fit_rms", "measured": fitinfo.get("radius_fit_rms_device", -1),
                     "expected": None, "delta": None, "tolerance": "-", "unit": "device px",
                     "pass": True})

    # Right flank: its visible sliver starts at the centre card's right edge + gap.
    flank = measure_card(lum, 2400, 965, 300, 760, args.smooth)
    rep.check("ref.flank.scale", flank["height"] / centre["height"], 0.9393,
              tol=TOL_SCALE, unit="ratio", scale_with_window=False)
    rep.check("ref.flank.height_css", rep.css(flank["height"]), 626.5, tol=3.0)

    rc = rep.emit(args.json)
    if rc == 0:
        print("\nH1 KNOWN-ANSWER PROOF: PASS -- reproduces VIDEO-REVIEW 1.1-1.3 "
              "from %s. The harness may grade." % args.reference)
    else:
        print("\nH1 KNOWN-ANSWER PROOF: FAIL -- this harness must not grade anything.")
    return rc


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--json", action="store_true", help="machine-readable report")
    p.add_argument("--backing-scale", type=float, default=2.0,
                   help="device px per CSS px in the image (row 119 asserts 2.0)")
    p.add_argument("--window-width", type=float, default=REFERENCE_VIEWPORT_CSS,
                   help="the window's logical width in CSS px, for ratio normalization")
    p.add_argument("--smooth", type=int, default=1, help="gradient smoothing radius in px")
    sub = p.add_subparsers(dest="cmd")

    c = sub.add_parser("card", help="measure a card box, radius and centre")
    c.add_argument("image")
    c.add_argument("--cx", type=float, required=True, help="a device-px x inside the card")
    c.add_argument("--cy", type=float, required=True, help="a device-px y inside the card")
    c.add_argument("--half-width", type=float, default=900.0,
                   help="search half-width in device px; MUST exceed half the card width")
    c.add_argument("--half-height", type=float, default=760.0,
                   help="search half-height in device px; MUST exceed half the card height")
    for name in ("width", "height", "center-x", "center-y", "radius"):
        c.add_argument("--expect-" + name, type=float, default=None,
                       help="expected %s in CSS px at W=1344" % name.replace("-", " "))
    c.add_argument("--radius", action="store_true", help="report radius even with no expectation")
    c.set_defaults(func=cmd_card)

    s = sub.add_parser("scale", help="measure a flank card's scale against the centre")
    s.add_argument("image")
    s.add_argument("--cx", type=float, required=True)
    s.add_argument("--cy", type=float, required=True)
    s.add_argument("--flank-cx", type=float, required=True)
    s.add_argument("--half-width", type=float, default=900.0)
    s.add_argument("--half-height", type=float, default=760.0)
    s.add_argument("--expect-scale", type=float, default=None)
    s.set_defaults(func=cmd_scale)

    k = sub.add_parser("color", help="sample a colour patch")
    k.add_argument("image")
    k.add_argument("--x", type=int, required=True)
    k.add_argument("--y", type=int, required=True)
    k.add_argument("--box", type=int, default=9)
    k.add_argument("--expect", default=None, help="#rrggbb")
    k.set_defaults(func=cmd_color)

    t = sub.add_parser("selftest", help="known-answer proof against the reference frame")
    t.add_argument("reference", help="path to video/hi/rest.png")
    t.set_defaults(func=cmd_selftest)

    args = p.parse_args(argv)
    if not getattr(args, "func", None):
        p.print_help()
        return 2
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
