// Modified 2026-09-03 for the cmux carousel build (carousel unit work).
#!/usr/bin/env python3
"""Wire the U5 carousel files into cmux.xcodeproj/project.pbxproj.

No file-system-synchronized groups exist in this project, so each Swift file
needs four entries: a PBXFileReference, a PBXBuildFile, a child line in its
PBXGroup, and a line in its target's PBXSourcesBuildPhase. A file missing the
last two compiles nowhere and its tests report "Executed 0 tests", which is the
exact failure ./scripts/lint-pbxproj-test-wiring.sh exists to catch.
"""
import hashlib, re, sys, pathlib

PBX = pathlib.Path("cmux.xcodeproj/project.pbxproj")
text = PBX.read_text()

SOURCES = sorted(p.as_posix() for p in pathlib.Path("Sources/Carousel").rglob("*.swift"))
TESTS   = sorted(p.as_posix() for p in pathlib.Path("cmuxTests").glob("Carousel*.swift")) + \
          sorted(p.as_posix() for p in pathlib.Path("cmuxTests").glob("Statusline*.swift"))

def uid(seed):
    # Deterministic 24-hex id in the project's own style, prefixed CA5E ("carousel")
    return ("CA5E" + hashlib.sha1(seed.encode()).hexdigest().upper())[:24]

def anchor_group_id(member_id):
    """The PBXGroup whose children list contains member_id.

    Children are NOT uniformly indented in this file (a handful of lines use two
    tabs where the rest use four), so the body is bounded by the closing paren
    rather than by a per-line indentation pattern.
    """
    for m in re.finditer(r"^\t\t([0-9A-F]{8,32}) /\* (.+?) \*/ = \{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = \(\n", text, re.M):
        end = text.find("\n\t\t\t);", m.end())
        if end != -1 and member_id in text[m.end():end]:
            return m.group(1), m.group(2)
    return None, None

def phase_for(target_name):
    """The PBXSourcesBuildPhase id belonging to the named native target."""
    tm = re.search(r"^\t\t([0-9A-F]{8,32}) /\* " + re.escape(target_name) + r" \*/ = \{\n\t\t\tisa = PBXNativeTarget;(.*?)\n\t\t\};", text, re.M | re.S)
    if not tm: sys.exit(f"native target {target_name} not found")
    ids = re.findall(r"([0-9A-F]{8,32}) /\* Sources \*/", tm.group(2))
    if not ids: sys.exit(f"no Sources phase for {target_name}")
    return ids[0]

# Anchors: a known-good existing member of each group.
src_anchor = "EA1F00000000000000000002"   # Sources/Sidebar/SidebarPathFormatter.swift
src_group, src_group_name = anchor_group_id(src_anchor)
if not src_group: sys.exit("could not locate the Sources group")

tm = re.search(r"^\t\t([0-9A-F]{8,32}) /\* (\S+Tests?\.swift) \*/ = \{isa = PBXFileReference;[^\n]*path = ([^;]+);", text, re.M)
test_anchor = None
for m in re.finditer(r"^\t\t([0-9A-F]{8,32}) /\* ([^*]+?) \*/ = \{isa = PBXFileReference;([^\n]*)\};", text, re.M):
    if "cmuxTests/" in m.group(3) or (m.group(2).endswith("Tests.swift")):
        gid, gname = anchor_group_id(m.group(1))
        if gid and "Test" in (gname or ""):
            test_anchor, test_group, test_group_name = m.group(1), gid, gname
            break
if not test_anchor: sys.exit("could not locate the cmuxTests group")

src_phase  = phase_for("cmux")
test_phase = phase_for("cmuxTests")
print(f"Sources group {src_group} ({src_group_name}) phase {src_phase}")
print(f"Tests   group {test_group} ({test_group_name}) phase {test_phase}")

def already(path):
    return f"path = {path.split('/',1)[1] if path.startswith('Sources/') else path};" in text

buildfiles, filerefs = [], []
group_adds = {src_group: [], test_group: []}
phase_adds = {src_phase: [], test_phase: []}

for path, group, phase, prefix in [(p, src_group, src_phase, "Sources/") for p in SOURCES] + \
                                  [(p, test_group, test_phase, "cmuxTests/") for p in TESTS]:
    name = path.rsplit("/", 1)[-1]
    rel = path[len(prefix):] if path.startswith(prefix) else path
    if f"/* {name} */ = {{isa = PBXFileReference" in text:
        print(f"  skip (already wired): {path}")
        continue
    fref, bfile = uid("ref:" + path), uid("build:" + path)
    # OpenStep pbxproj quotes any value that is not a bare token. A path holding
    # "+" (the repo's own convention for extension files, e.g.
    # ContentView+SavedLayoutCommands.swift) MUST be quoted or Xcode reports the
    # whole project as damaged. Verified against the existing entries.
    quoted = rel if re.fullmatch(r"[A-Za-z0-9_./-]+", rel) else '"' + rel + '"'
    filerefs.append(f"\t\t{fref} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {quoted}; sourceTree = \"<group>\"; }};")
    buildfiles.append(f"\t\t{bfile} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {fref} /* {name} */; }};")
    group_adds[group].append(f"\t\t\t\t{fref} /* {name} */,")
    phase_adds[phase].append(f"\t\t\t\t{bfile} /* {name} in Sources */,")
    print(f"  wire: {path}")

if not filerefs:
    print("nothing to wire"); sys.exit(0)

text = text.replace("/* End PBXBuildFile section */", "\n".join(buildfiles) + "\n/* End PBXBuildFile section */", 1)
text = text.replace("/* End PBXFileReference section */", "\n".join(filerefs) + "\n/* End PBXFileReference section */", 1)

for gid, lines in group_adds.items():
    if not lines: continue
    m = re.search(r"(\t\t" + gid + r" /\* .+? \*/ = \{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = \(\n)", text)
    text = text[:m.end(1)] + "\n".join(lines) + "\n" + text[m.end(1):]

for pid, lines in phase_adds.items():
    if not lines: continue
    m = re.search(r"(\t\t" + pid + r" /\* Sources \*/ = \{\n(?:\t\t\t.*\n)*?\t\t\tfiles = \(\n)", text)
    text = text[:m.end(1)] + "\n".join(lines) + "\n" + text[m.end(1):]

PBX.write_text(text)
print(f"wired {len(filerefs)} files")
