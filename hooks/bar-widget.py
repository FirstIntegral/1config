#!/usr/bin/env python3
"""bar-widget.py — add firstintegral.1config to bar.layout.right in Omarchy's shell.json.

    python3 ~/.agents/hooks/bar-widget.py <shell.json> <backup-dir>     # setup.sh runs this

The id goes after `brwsk.vigil` when that widget is on the bar, else at the
start of the right side (ADR 2026-10-15). The edit is a text insert, so the
file keeps the formatting Omarchy and the user gave it. Because it is a text
insert, it is fenced on both sides: the file must parse as JSON with a
bar.layout.right list before, and the result must parse and differ from the
old list by exactly the one new id. Otherwise nothing is written. The previous
file is copied to the backup dir and the new one replaces it atomically.

Always exits 0: a bar that could not be edited is a printed line, not a failed
setup. verify.sh checks that the id is on the bar.
"""
import collections
import json
import os
import sys
from pathlib import Path

WIDGET = "firstintegral.1config"
ANCHOR = "brwsk.vigil"


def ids_on_the_right(doc):
    """Widget ids in bar.layout.right, or None when the text is not that JSON."""
    try:
        right = json.loads(doc)["bar"]["layout"]["right"]
    except (ValueError, KeyError, TypeError):
        return None
    if not isinstance(right, list):
        return None
    return [w.get("id") if isinstance(w, dict) else None for w in right]


def insert(text):
    """Return (new_text, line_number) or (None, reason)."""
    before = ids_on_the_right(text)
    if before is None:
        return None, "shell.json is not plain JSON with a bar.layout.right list"
    lines = text.splitlines(keepends=True)
    # Candidate lines to insert before: after the anchor widget, then the start
    # of the right side. The first one that yields a valid file wins, so an
    # anchor that is the last entry (no "}," after it) falls through.
    candidates = []
    for i, line in enumerate(lines):
        if f'"id": "{ANCHOR}"' in line:
            for j in range(i, len(lines)):
                if lines[j].strip() == "},":
                    candidates.append(j + 1)
                    break
            break
    for i, line in enumerate(lines):
        if '"right"' in line and "[" in line:
            candidates.append(i + 1)
            break
    if not candidates:
        return None, "no line opens bar.layout.right"
    for insert_at in candidates:
        k = insert_at
        while k < len(lines) and lines[k].strip() == "":
            k += 1
        last = k < len(lines) and lines[k].strip().startswith("]")
        entry = f'        {{\n          "id": "{WIDGET}"\n        }}' + ("\n" if last else ",\n")
        new_text = "".join(lines[:insert_at] + [entry] + lines[insert_at:])
        after = ids_on_the_right(new_text)
        if after is not None and collections.Counter(after) == collections.Counter(before + [WIDGET]):
            return new_text, insert_at + 1
    return None, "the edited file would not parse, or would change more than one entry"


def main():
    if len(sys.argv) != 3:
        print("usage: bar-widget.py <shell.json> <backup-dir>", file=sys.stderr)
        return 2
    path, backup_dir = Path(sys.argv[1]), Path(sys.argv[2])
    if not path.is_file():
        print("  no shell.json — plugin copied, bar not edited")
        return 0
    text = path.read_text()
    current = ids_on_the_right(text)
    if current is not None and WIDGET in current:
        print(f"  bar already has {WIDGET}")
        return 0
    new_text, where = insert(text)
    if new_text is None:
        print(f"  WARNING: bar not edited — {where}. Add {WIDGET} to bar.layout.right by hand.")
        return 0
    backup_dir.mkdir(parents=True, exist_ok=True)
    (backup_dir / "shell.json").write_text(text)
    tmp = path.with_name(path.name + ".1config-tmp")
    tmp.write_text(new_text)
    os.replace(tmp, path)
    print(f"  inserted {WIDGET} at line {where} (previous file: {backup_dir / 'shell.json'})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
