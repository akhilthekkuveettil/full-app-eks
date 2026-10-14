#!/usr/bin/env python3
"""Rewrite the image digests in deploy/envs/prod.yaml.

Usage: bump_digests.py <values-file> backend1=sha256:... backend2=sha256:... frontend=sha256:...

Only the digest lines are touched, so comments and formatting in the file are preserved.
Prints "<service> <old> -> <new>" for every change and exits 0 even when nothing changed.
"""
import re
import sys

DIGEST = re.compile(r"^sha256:[0-9a-f]{64}$")


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__, file=sys.stderr)
        return 2

    path, pairs = sys.argv[1], sys.argv[2:]
    new = {}
    for pair in pairs:
        name, _, digest = pair.partition("=")
        if not DIGEST.match(digest):
            print(f"invalid digest for {name!r}: {digest!r}", file=sys.stderr)
            return 2
        new[name] = digest

    with open(path) as f:
        lines = f.read().split("\n")

    in_frontend = False
    changed = set()
    for i, line in enumerate(lines):
        if re.match(r"^frontend:\s*$", line):
            in_frontend = True
            continue
        if in_frontend and line and not line.startswith(" "):
            in_frontend = False

        m = re.match(r'^(\s+)(backend\d+):\s*\{\s*digest:\s*"(sha256:[0-9a-f]{64})"\s*\}\s*$', line)
        if m and m.group(2) in new:
            name, old = m.group(2), m.group(3)
            lines[i] = f'{m.group(1)}{name}: {{ digest: "{new[name]}" }}'
            changed.add(name)
            if old != new[name]:
                print(f"{name} {old[:19]} -> {new[name][:19]}")
            continue

        m = re.match(r'^(\s+)digest:\s*"(sha256:[0-9a-f]{64})"\s*$', line)
        if m and in_frontend and "frontend" in new:
            old = m.group(2)
            lines[i] = f'{m.group(1)}digest: "{new["frontend"]}"'
            changed.add("frontend")
            if old != new["frontend"]:
                print(f"frontend {old[:19]} -> {new['frontend'][:19]}")

    missing = set(new) - changed
    if missing:
        print(f"no digest line found for: {', '.join(sorted(missing))}", file=sys.stderr)
        return 1

    with open(path, "w") as f:
        f.write("\n".join(lines))
    return 0


if __name__ == "__main__":
    sys.exit(main())
