#!/usr/bin/env python3
"""Keep $HOME from becoming an agent workspace.

Grok's Cursor shell writes <workspace>/terminals and <workspace>/agent-tools
by itself. When the session was started in $HOME those land in the home
directory. This script deletes a directory only when every entry matches that
spill signature. A file that does not match is left in place and the run
exits 2.

pretool reads a Grok/Claude PreToolUse payload on stdin. It denies a create
whose first path segment under $HOME is a new non-dot name. Reads, edits of
an existing top-level name, dot-paths, and paths under an existing directory
(such as ~/Projects/...) are left alone.
"""

from __future__ import annotations

import json
import os
import re
import sys
import time
from pathlib import Path

AGENT_TOOLS_MAX_AGE_S = 600
UUID_TXT = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.txt$"
)
RUNNING = re.compile(r"(?m)^status:\s*running\s*$")
CREATOR = re.compile(
    r"(?:^|[;&|(`\n]|&&|\|\|)\s*(?:sudo\s+|command\s+)?"
    r"(?:mkdir|touch|tee|cp|mv|install|ln|rsync)\b"
)
REDIRECT = re.compile(r">>?\s*(\S+)")
PATH_TOKEN = re.compile(r"(?:~|\$\{?HOME\}?|/[^\s;|&\"']+)/[^\s;|&\"']+")


def home() -> Path:
    return Path(os.environ.get("HOME", str(Path.home()))).resolve()


def warn(msg: str) -> None:
    print(f"home-spill-guard: {msg}", file=sys.stderr)


def spill_dir(name: str) -> tuple[Path | None, int]:
    """Return the directory when it is a real directory directly under $HOME.

    The status is 2 when the path exists but is not safe to treat as spill.
    """
    root = home()
    path = root / name
    if path.is_symlink():
        warn(f"{path} is a symlink — left untouched")
        return None, 2
    if not path.exists():
        return None, 0
    if not path.is_dir():
        warn(f"{path} is not a directory — left untouched")
        return None, 2
    try:
        resolved = path.resolve()
    except OSError as exc:
        warn(f"{path} resolve failed ({exc}) — left untouched")
        return None, 2
    if resolved.parent != root:
        warn(f"{path} resolves outside $HOME — left untouched")
        return None, 2
    return path, 0


def terminal_head(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8", errors="replace")[:4000]
    except OSError:
        return ""


def terminals_sweep(path: Path) -> int:
    """Delete finished terminal logs. Keep a file whose status is running.

    Returns 0 when the directory was clean spill (or already gone), 2 when
    an entry did not match and nothing was deleted.
    """
    entries = list(path.iterdir())
    if not entries:
        path.rmdir()
        return 0
    bad = []
    running = []
    finished = []
    for entry in entries:
        if entry.is_symlink() or not entry.is_file() or entry.suffix != ".txt":
            bad.append(entry.name)
            continue
        head = terminal_head(entry)
        if not head.startswith("---") or "running_for_ms:" not in head:
            bad.append(entry.name)
            continue
        if RUNNING.search(head):
            running.append(entry)
        else:
            finished.append(entry)
    if bad:
        warn(f"{path} has non-spill entries ({', '.join(bad[:5])}) — left untouched")
        return 2
    for entry in finished:
        entry.unlink()
    if not running:
        path.rmdir()
    return 0


def agent_tools_sweep(path: Path) -> int:
    entries = list(path.iterdir())
    if not entries:
        path.rmdir()
        return 0
    now = time.time()
    bad = []
    stale = []
    for entry in entries:
        if entry.is_symlink() or not entry.is_file() or not UUID_TXT.match(entry.name):
            bad.append(entry.name)
            continue
        try:
            age = now - entry.stat().st_mtime
        except OSError:
            bad.append(entry.name)
            continue
        if age >= AGENT_TOOLS_MAX_AGE_S:
            stale.append(entry)
    if bad:
        warn(f"{path} has non-spill entries ({', '.join(bad[:5])}) — left untouched")
        return 2
    for entry in stale:
        entry.unlink()
    if not any(path.iterdir()):
        path.rmdir()
    return 0


def sweep() -> int:
    code = 0
    terminals, status = spill_dir("terminals")
    code = max(code, status)
    if terminals is not None:
        code = max(code, terminals_sweep(terminals))
    tools, status = spill_dir("agent-tools")
    code = max(code, status)
    if tools is not None:
        code = max(code, agent_tools_sweep(tools))
    return code


def expand_path(raw: str) -> Path | None:
    text = raw.strip().strip("'\"")
    if not text or text.startswith("-"):
        return None
    root = str(home())
    text = text.replace("${HOME}", root).replace("$HOME", root)
    if text.startswith("~"):
        text = str(Path(text).expanduser())
    path = Path(text)
    if not path.is_absolute():
        return None
    return path


def new_home_child(raw: str) -> str | None:
    """First non-dot segment under $HOME when that segment does not exist yet."""
    path = expand_path(raw)
    if path is None:
        return None
    root = home()
    try:
        rel = path.resolve().relative_to(root)
    except ValueError:
        try:
            rel = Path(os.path.abspath(path)).relative_to(root)
        except ValueError:
            return None
    if not rel.parts:
        return None
    segment = rel.parts[0]
    if segment.startswith("."):
        return None
    if os.path.lexists(root / segment):
        return None
    return segment


def command_targets(command: str) -> list[str]:
    found: list[str] = []
    if CREATOR.search(command):
        found.extend(PATH_TOKEN.findall(command))
    found.extend(REDIRECT.findall(command))
    return found


def payload_paths(payload: dict) -> list[str]:
    tool_input = payload.get("tool_input") or payload.get("toolInput") or {}
    if isinstance(tool_input, str):
        try:
            tool_input = json.loads(tool_input)
        except json.JSONDecodeError:
            tool_input = {}
    if not isinstance(tool_input, dict):
        return []
    paths: list[str] = []
    command = tool_input.get("command")
    if isinstance(command, str):
        paths.extend(command_targets(command))
    for key in ("file_path", "path", "target_file"):
        value = tool_input.get(key)
        if isinstance(value, str):
            paths.append(value)
    return paths


def pretool() -> int:
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return 0
    if not isinstance(payload, dict):
        return 0
    hits = []
    for raw in payload_paths(payload):
        segment = new_home_child(raw)
        if segment and segment not in hits:
            hits.append(segment)
    if not hits:
        return 0
    names = ", ".join(f"$HOME/{name}" for name in hits)
    reason = (
        f"Home is not a project. Refusing to create {names}. "
        "Put new work in ~/Projects/<name> or /tmp. "
        "terminals/ and agent-tools/ directly under $HOME are Grok shell spill, not projects."
    )
    json.dump({"decision": "deny", "reason": reason}, sys.stdout)
    sys.stdout.write("\n")
    return 0


def main() -> int:
    mode = sys.argv[1] if len(sys.argv) > 1 else "sweep"
    if mode in ("sweep", "sweep-live"):
        return sweep()
    if mode == "pretool":
        return pretool()
    warn("usage: home-spill-guard.py sweep|pretool")
    return 2


if __name__ == "__main__":
    sys.exit(main())
