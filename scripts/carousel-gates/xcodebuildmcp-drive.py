#!/usr/bin/env python3
# Modified 2026-09-02 for the cmux carousel build (cmux-carousel-ui CONTRACT row 111).
"""Drive XcodeBuildMCP over stdio JSON-RPC and prove a build and a test call.

Row 111 requires the build and the test to go THROUGH XcodeBuildMCP, not through a
raw xcodebuild, and requires both green. Three things about this server make a naive
driver fail, all found by provisioning and all handled here:

1. macOS workflow tools are NOT enabled by default -- only session-management and
   simulator load. `build_macos`, `test_macos` and friends appear only when a project
   config file at <project>/.xcodebuildmcp/config.yaml lists the `macos` workflow.
   An env var does not exist for this in this version.

2. The tools do NOT accept projectPath / scheme / configuration / derivedDataPath as
   arguments; the public schema omits them. The flow is `session_set_defaults` first,
   then `build_macos` / `test_macos` with empty arguments, reading from session state.

3. The server EXITS ON STDIN EOF. A `cat file | npx ... mcp` pipe therefore kills it
   before an in-flight build resolves. stdin is held open for the whole exchange here.

And one thing that bit provisioning: sending build and test back to back WITHOUT
waiting for the first response makes the server run them CONCURRENTLY against the same
derivedDataPath, which is a self-inflicted copy of the exact race that broke the first
provisioning build. Every call waits for its response.

  xcodebuildmcp-drive.py --project <dir> --scheme cmux --derived-data <path> build
  xcodebuildmcp-drive.py --project <dir> --scheme cmux --derived-data <path> test
  xcodebuildmcp-drive.py --project <dir> tools        # list what is actually exposed
"""

import argparse
import json
import os
import subprocess
import sys
import threading
import time


class MCPClient(object):
    def __init__(self, cwd, env=None, verbose=False):
        self.verbose = verbose
        self.proc = subprocess.Popen(
            ["npx", "-y", "xcodebuildmcp@latest", "mcp"],
            cwd=cwd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, bufsize=1,
            env=dict(os.environ, **(env or {})))
        self._id = 0
        self._stderr = []
        t = threading.Thread(target=self._drain, daemon=True)
        t.start()

    def _drain(self):
        for line in self.proc.stderr:
            self._stderr.append(line.rstrip())
            if self.verbose:
                sys.stderr.write("[server] " + line)

    def call(self, method, params=None, timeout=3600):
        self._id += 1
        msg = {"jsonrpc": "2.0", "id": self._id, "method": method}
        if params is not None:
            msg["params"] = params
        self.proc.stdin.write(json.dumps(msg) + "\n")
        self.proc.stdin.flush()
        deadline = time.time() + timeout
        while time.time() < deadline:
            line = self.proc.stdout.readline()
            if not line:
                raise RuntimeError("server closed stdout; last stderr:\n"
                                   + "\n".join(self._stderr[-15:]))
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except ValueError:
                continue
            # Notifications and progress messages carry no id; keep reading.
            if obj.get("id") != self._id:
                continue
            if "error" in obj:
                raise RuntimeError("%s failed: %s" % (method, json.dumps(obj["error"])))
            return obj.get("result", {})
        raise RuntimeError("%s timed out after %ss" % (method, timeout))

    def notify(self, method, params=None):
        msg = {"jsonrpc": "2.0", "method": method}
        if params is not None:
            msg["params"] = params
        self.proc.stdin.write(json.dumps(msg) + "\n")
        self.proc.stdin.flush()

    def close(self):
        try:
            self.proc.stdin.close()
        except Exception:
            pass
        try:
            self.proc.wait(timeout=20)
        except Exception:
            self.proc.kill()


def text_of(result):
    out = []
    for block in result.get("content", []) or []:
        if block.get("type") == "text":
            out.append(block.get("text", ""))
    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("action", choices=("build", "test", "tools"))
    ap.add_argument("--project", required=True, help="repo root containing cmux.xcodeproj")
    ap.add_argument("--scheme", default="cmux")
    ap.add_argument("--configuration", default="Debug")
    ap.add_argument("--derived-data", default=None)
    ap.add_argument("--timeout", type=int, default=5400)
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()

    # Requirement 1: the macos workflow must be enabled by an on-disk project config.
    cfg_dir = os.path.join(args.project, ".xcodebuildmcp")
    cfg = os.path.join(cfg_dir, "config.yaml")
    if not os.path.exists(cfg):
        os.makedirs(cfg_dir, exist_ok=True)
        with open(cfg, "w") as fh:
            fh.write("schemaVersion: 1\n"
                     "enabledWorkflows:\n  - session-management\n  - simulator\n  - macos\n"
                     "sentryDisabled: true\n")
        print("wrote %s (the macos workflow is not enabled by default)" % cfg)

    c = MCPClient(args.project, env={"SENTRY_DISABLED": "true"}, verbose=args.verbose)
    try:
        c.call("initialize", {"protocolVersion": "2024-11-05",
                              "capabilities": {},
                              "clientInfo": {"name": "cmux-carousel-u7", "version": "1"}})
        c.notify("notifications/initialized")
        tools = c.call("tools/list").get("tools", [])
        names = sorted(t["name"] for t in tools)
        if args.action == "tools":
            print("%d tools exposed:" % len(names))
            for n in names:
                print("  " + n)
            return 0
        need = "build_macos" if args.action == "build" else "test_macos"
        if need not in names:
            print("MISSING TOOL %s. Exposed: %s" % (need, ", ".join(names)), file=sys.stderr)
            print("The macos workflow did not load. Check %s." % cfg, file=sys.stderr)
            return 2

        # Requirement 2: parameters go through session defaults, not tool arguments.
        defaults = {"projectPath": os.path.join(args.project, "cmux.xcodeproj"),
                    "scheme": args.scheme,
                    "configuration": args.configuration}
        if args.derived_data:
            defaults["derivedDataPath"] = args.derived_data
        r = c.call("tools/call", {"name": "session_set_defaults", "arguments": defaults})
        print("session_set_defaults: %s" % text_of(r).strip()[:400])

        # Requirement 3 and the concurrency note: one call, waited out to completion.
        started = time.time()
        r = c.call("tools/call", {"name": need, "arguments": {}}, timeout=args.timeout)
        body = text_of(r)
        elapsed = time.time() - started
        print("\n=== %s (%.0fs) ===" % (need, elapsed))
        print(body[-6000:])
        failed = bool(r.get("isError")) or ("BUILD FAILED" in body) or ("TEST FAILED" in body)
        print("\nROW 111 (%s via XcodeBuildMCP): %s" % (args.action, "FAIL" if failed else "PASS"))
        return 1 if failed else 0
    finally:
        c.close()


if __name__ == "__main__":
    raise SystemExit(main())
