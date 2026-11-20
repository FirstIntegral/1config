#!/usr/bin/env python3
"""effective-perms.py — permissions.json with this machine's local.json laid over it.

  effective-perms.py --perms permissions.json [--local local.json]    JSON on stdout

setup.sh fans the result out to the tools, and verify.sh checks the tools
against the same result, so the overlay has one reader. The two keys in FLAGS
are the only ones read here. `caveman` belongs to hooks/local-rules.py.

A value must be a JSON true or false. The string "false" is refused: Python
reads every non-empty string as true, which would turn autonomy ON for a person
who wrote the opposite. Exit 2 names the key. A local.json that is not a JSON
object is exit 2 as well. One line per overlaid key goes to stderr.
"""
import argparse
import json
import pathlib
import sys

FLAGS = ("bash_without_prompt", "edit_without_prompt")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--perms", required=True)
    ap.add_argument("--local", default=None)
    args = ap.parse_args()

    canon = json.loads(pathlib.Path(args.perms).read_text())
    local = pathlib.Path(args.local) if args.local else None
    if local is None or not local.is_file():
        print("  overlay  no local.json (committed defaults)", file=sys.stderr)
        json.dump(canon, sys.stdout)
        return 0
    try:
        over = json.loads(local.read_text())
    except ValueError as exc:
        print(f"local.json is not valid JSON: {exc}", file=sys.stderr)
        return 2
    if not isinstance(over, dict):
        print("local.json must be a JSON object", file=sys.stderr)
        return 2
    defaults = canon.setdefault("defaults", {})
    seen = False
    for key in FLAGS:
        if key not in over:
            continue
        value = over[key]
        if not isinstance(value, bool):
            print(f"local.json {key} must be true or false without quotes, not {json.dumps(value)}",
                  file=sys.stderr)
            return 2
        defaults[key] = value
        seen = True
        print(f"  overlay  local.json {key}={str(value).lower()}", file=sys.stderr)
    if not seen:
        print("  overlay  local.json present, neither autonomy flag set", file=sys.stderr)
    json.dump(canon, sys.stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main())
