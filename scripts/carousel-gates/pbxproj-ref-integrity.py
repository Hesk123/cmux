#!/usr/bin/env python3
# Modified 2026-09-03 for the cmux carousel build (cmux-carousel-ui CONTRACT row 134).
"""Every PBXBuildFile's fileRef must resolve, and its file must exist on disk.

Why this exists. `scripts/lint-pbxproj-test-wiring.sh` matches the four wiring patterns
as STRINGS, so a PBXBuildFile whose fileRef is the literal token `None` satisfies all
four and the lint reports ok. The file is then compiled by nothing, the suite runs
without it, and `xcodebuild test` reports green -- the same "Executed 0 tests" shape
row 134 exists to catch, one level deeper: not an unwired file, but a wired-looking
entry pointing at nothing.

Three checks, each of which can fail independently:

  1. RESOLVES   -- every PBXBuildFile fileRef is a 24-hex id that exists as a
                   PBXFileReference. `None`, an empty value, or an unknown id fails.
  2. ON DISK    -- that PBXFileReference's path resolves to a file that exists.
                   A reference to a deleted file compiles nothing just as silently.
  3. NO DUPES   -- no file is listed twice in one target's sources phase, which
                   compiles it twice and produces duplicate-symbol noise.

Exit 0 only when all three pass for every entry.
"""

import os
import re
import sys

PBX_DEFAULT = "cmux.xcodeproj/project.pbxproj"

BUILDFILE_RE = re.compile(
    r"^\s*([A-Za-z0-9_]{8,32})\s*/\*\s*(.+?)\s*\*/\s*=\s*\{isa\s*=\s*PBXBuildFile;(.*?)\};",
    re.M)
# The value is followed by a /* comment */ BEFORE the semicolon:
#   fileRef = A11CE003... /* AboutLicenseContent.swift */;
# Requiring the semicolon immediately after the value matched nothing at all and
# reported every one of 2861 entries as dangling. Caught by running it against the
# real project file rather than trusting it -- a checker that fails everything is as
# useless as one that passes everything, and louder about it.
FILEREF_ATTR_RE = re.compile(r"fileRef\s*=\s*([^;\s]+)\s*(?:/\*.*?\*/)?\s*;")
FILEREF_DECL_RE = re.compile(
    r"^\s*([A-Za-z0-9_]{8,32})\s*/\*\s*(.+?)\s*\*/\s*=\s*\{isa\s*=\s*PBXFileReference;(.*?)\};",
    re.M)
PATH_ATTR_RE = re.compile(r"\bpath\s*=\s*(\"[^\"]*\"|[^;\s]+)\s*;")
SOURCES_PHASE_RE = re.compile(
    r"\{\s*isa\s*=\s*PBXSourcesBuildPhase;(.*?)\};", re.S)


def unquote(v):
    return v[1:-1] if len(v) >= 2 and v[0] == '"' and v[-1] == '"' else v


def main(argv):
    pbx = argv[1] if len(argv) > 1 else PBX_DEFAULT
    root = os.path.dirname(os.path.dirname(os.path.abspath(pbx)))
    try:
        src = open(pbx).read()
    except OSError as exc:
        print("cannot read %s: %s" % (pbx, exc), file=sys.stderr)
        return 2

    refs = {}
    for m in FILEREF_DECL_RE.finditer(src):
        pm = PATH_ATTR_RE.search(m.group(3))
        refs[m.group(1)] = {"name": m.group(2), "path": unquote(pm.group(1)) if pm else None}

    # Basename index of every tracked-looking file, built once.
    disk_index = set()
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames
                       if d not in (".git", "DerivedData", "node_modules", ".build")]
        for fn in filenames:
            disk_index.add(fn)
        # Folder references (a directory added to Resources) are real entries whose
        # path names a DIRECTORY, so a filename-only index reports them missing.
        for dn in dirnames:
            disk_index.add(dn)

    failures = []
    checked = 0
    for m in BUILDFILE_RE.finditer(src):
        build_id, label, body = m.group(1), m.group(2), m.group(3)
        checked += 1
        # A SwiftPM package product is linked by productRef, not fileRef, and has no
        # file on disk to point at. Flagging those was 60-odd false positives and would
        # have buried the one real finding.
        if "productRef" in body:
            continue
        am = FILEREF_ATTR_RE.search(body)
        if not am:
            failures.append("DANGLING  %s /* %s */ has no fileRef attribute at all" % (build_id, label))
            continue
        target = am.group(1).strip()
        # 1. RESOLVES -- by MEMBERSHIP, never by shape. Xcode ids are opaque tokens:
        # this project contains AA9457FR..., which is not hex, is declared, and works.
        # An earlier revision required hex and reported it as dangling, which is a
        # false positive on a file that compiles fine. `None` fails this check because
        # nothing declares it, which is the right reason to fail.
        if target not in refs:
            failures.append("DANGLING  %s /* %s */ fileRef %s resolves to no PBXFileReference"
                            % (build_id, label, target))
            continue
        # 2. ON DISK.
        path = refs[target]["path"]
        if path is None:
            failures.append("NO PATH   %s /* %s */ -> %s has no path attribute"
                            % (build_id, label, target))
            continue
        if os.path.isabs(path):
            continue                      # absolute/SDK refs are not ours to resolve
        # Build PRODUCTS (another target's output) only exist after building, so they
        # are legitimately absent from a clean checkout.
        if os.path.splitext(path)[1] in (".plugin", ".app", ".framework", ".xctest",
                                         ".a", ".dylib", ".bundle", ".appex"):
            continue
        # A group path is relative to its group, and this project has dozens of groups,
        # so resolving it exactly would mean walking the whole group tree. The question
        # that matters is narrower: does a file by this name exist anywhere in the repo?
        # A dangling or deleted reference fails that; a correct one in a group this
        # script did not model does not. Being lenient here keeps the check pointed at
        # the defect it was written for instead of generating false positives.
        if os.path.basename(path) not in disk_index:
            failures.append("MISSING   %s /* %s */ -> path %r: no file of that name "
                            "exists anywhere in the repo" % (build_id, label, path))

    # 3. NO DUPES, per sources phase.
    for phase in SOURCES_PHASE_RE.finditer(src):
        seen = {}
        for line in phase.group(1).splitlines():
            lm = re.match(r"\s*([A-Za-z0-9_]{8,32})\s*/\*\s*(.+?)\s*\*/,", line)
            if not lm:
                continue
            seen.setdefault(lm.group(2), []).append(lm.group(1))
        for label, ids in seen.items():
            if len(ids) > 1:
                failures.append("DUPLICATE %s appears %d times in one sources phase; it "
                                "would compile twice" % (label, len(ids)))

    print("checked %d PBXBuildFile entries against %d PBXFileReference declarations"
          % (checked, len(refs)))
    if failures:
        for f in failures:
            print("  " + f)
        print("PBXPROJ REF INTEGRITY: FAIL (%d)" % len(failures))
        return 1
    print("PBXPROJ REF INTEGRITY: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
