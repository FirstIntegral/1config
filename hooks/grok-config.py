#!/usr/bin/env python3
"""grok-config.py — set the three switches 1config needs in ~/.grok/config.toml.

    python3 ~/.agents/hooks/grok-config.py switches FILE           # setup.sh step 2
    python3 ~/.agents/hooks/grok-config.py switches FILE --check   # preflight: write nothing

The switches:

    [compat.claude]  agents = false     Grok does not read CLAUDE.md a second time
    [compat.claude]  rules  = false
    [memory]         enabled = false    memory lives in shared markdown

Python has a TOML reader and no TOML writer, so this edits lines. A line edit
can break a file that names the same table another way (a header with a comment
after it, a dotted key such as `memory.enabled = true`, an inline table). So
the result is parsed before it is written, and the three values are read back
from the parse. A result that does not parse, or that does not hold the values,
is not written: the script exits 1 and says which key to set by hand.

--check also refuses a [permission] table with keys other than allow, ask, and
deny. setup.sh replaces that table from permissions.json and stops on such a
key, and the preflight is the place to say so: before anything is written.

Exit 0 done, or nothing to do · 1 the file cannot be edited safely · 2 usage.
"""
import pathlib
import re
import sys
import tomllib

WANTED = [
    ("compat.claude", "agents", False),
    ("compat.claude", "rules", False),
    ("memory", "enabled", False),
]
HEADER = re.compile(r"^\s*\[\[?\s*([A-Za-z0-9_.\- ]+?)\s*\]\]?\s*(#.*)?$")


def fail(msg):
    print(f"grok-config: {msg}", file=sys.stderr)
    sys.exit(1)


def table_at(data, dotted):
    node = data
    for part in dotted.split("."):
        if not isinstance(node, dict) or part not in node:
            return None
        node = node[part]
    return node if isinstance(node, dict) else None


def header_name(line):
    m = HEADER.match(line)
    if not m or line.lstrip().startswith("[["):
        return None
    return re.sub(r"\s*\.\s*", ".", m.group(1).strip())


def section_span(lines, name):
    """(start, end) of the table whose header is [name], or None."""
    for i, line in enumerate(lines):
        if header_name(line) == name:
            end = next((j for j in range(i + 1, len(lines)) if HEADER.match(lines[j])), len(lines))
            return i, end
    return None


def set_in_span(lines, start, end, key, literal):
    """Replace `key = ...` between start and end. True when a line was replaced."""
    pat = re.compile(rf"^(\s*){re.escape(key)}\s*=\s*[^#]*?(\s*#.*)?$")
    for i in range(start, end):
        m = pat.match(lines[i])
        if m:
            lines[i] = f"{m.group(1)}{key} = {literal}{m.group(2) or ''}"
            return True
    return False


def set_key(text, section, key, value):
    literal = "true" if value else "false"
    lines = text.splitlines()
    span = section_span(lines, section)
    if span is not None:
        start, end = span
        if not set_in_span(lines, start + 1, end, key, literal):
            lines.insert(start + 1, f"{key} = {literal}")
        return "\n".join(lines) + "\n"
    try:
        defined = table_at(tomllib.loads(text), section) is not None
    except tomllib.TOMLDecodeError:
        defined = False
    if not defined:
        return text.rstrip("\n") + f"\n\n[{section}]\n{key} = {literal}\n"
    # The table exists, but not under its own header: a dotted key carries it.
    # Try each place such a key can sit, from the top of the file inwards.
    parts = section.split(".")
    for depth in range(len(parts)):
        parent = ".".join(parts[:depth])
        dotted = ".".join(parts[depth:] + [key])
        if parent:
            span = section_span(lines, parent)
            if span is None:
                continue
            start, end = span[0] + 1, span[1]
        else:
            start = 0
            end = next((j for j in range(len(lines)) if HEADER.match(lines[j])), len(lines))
        if set_in_span(lines, start, end, dotted, literal):
            return "\n".join(lines) + "\n"
    return None


def main():
    args = sys.argv[1:]
    check = "--check" in args
    args = [a for a in args if a != "--check"]
    if len(args) != 2 or args[0] != "switches":
        print("usage: grok-config.py switches FILE [--check]", file=sys.stderr)
        return 2
    path = pathlib.Path(args[1])
    existed = path.exists()
    text = path.read_text() if existed else "# grok config — created by ~/.agents/setup.sh\n"
    try:
        before = tomllib.loads(text)
    except tomllib.TOMLDecodeError as e:
        fail(f"{path} is not valid TOML ({e}). Fix it, or move it away and let Grok write a new one.")
    if check:
        perm = before.get("permission", {})
        extra = sorted(set(perm) - {"allow", "ask", "deny"}) if isinstance(perm, dict) else ["permission"]
        if extra:
            fail(f"{path} has [permission] keys that setup.sh would drop: {', '.join(extra)}. "
                 "Move them to permissions.json in your fork, or delete them.")
    for section, key, value in WANTED:
        new = set_key(text, section, key, value)
        if new is None:
            fail(f"{path} defines [{section}] in a form this script does not edit. "
                 f"Set {key} = {'true' if value else 'false'} in [{section}] by hand, then run setup.sh again.")
        text = new
    try:
        after = tomllib.loads(text)
    except tomllib.TOMLDecodeError as e:
        fail(f"the edit of {path} would not parse ({e}). Nothing was written. "
             "Set agents = false and rules = false in [compat.claude], and enabled = false in [memory], by hand.")
    for section, key, value in WANTED:
        table = table_at(after, section)
        if table is None or table.get(key) is not value:
            fail(f"the edit of {path} did not set [{section}] {key}. Nothing was written. Set it by hand.")
    if check:
        return 0
    if existed and path.read_text() == text:
        print("  ok       [compat.claude] agents/rules=false, [memory] enabled=false already set")
        return 0
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    print("  set      [compat.claude] agents/rules=false, [memory] enabled=false")
    return 0


if __name__ == "__main__":
    sys.exit(main())
