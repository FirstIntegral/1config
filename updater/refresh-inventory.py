#!/usr/bin/env python3
"""Write machine-local CLI versions to inventory.local.md (gitignored).

Live grok/claude/opencode versions differ across machines and must not be
committed into SETUP.md — that made a Ubuntu box fail verify after pulling
Omarchy versions, and the other way around.

All probes run through a login shell (bash -lc) so the inventory always
reflects the PATH-resolved binary (mise shims included) no matter what
environment the caller (boot cron, resume hook, interactive shell) has.
"""

import datetime
import os
import pathlib
import re
import subprocess
import sys

START = "<!-- TOOL_INVENTORY_START -->"
END = "<!-- TOOL_INVENTORY_END -->"


def login_shell(cmd: str) -> str:
    # env -i: canonical login resolution, independent of the caller's PATH
    # (boot cron, updater's exported PATH, and AI harnesses all differ).
    try:
        result = subprocess.run(
            ["env", "-i", f"HOME={pathlib.Path.home()}", "TERM=dumb", "bash", "-lc", cmd],
            capture_output=True, text=True, timeout=60, check=False,
        )
        return (result.stdout or result.stderr or "").strip()
    except (OSError, subprocess.SubprocessError):
        return ""


def resolve(binary: str) -> str:
    out = login_shell(f"command -v {binary}")
    path = os.path.normpath(out.splitlines()[0]) if out else ""
    return path.replace(str(pathlib.Path.home()), "~", 1) if path else "missing"


def version(binary: str) -> str:
    out = login_shell(f"{binary} --version")
    value = out.splitlines()[0] if out else "unknown"
    match = re.search(r"(\d+\.\d+\.\d+)", value)
    return match.group(1) if match else (value[:40] or "unknown")


def table() -> str:
    return (
        "| Tool | Version | Binary | Config |\n"
        "|------|---------|--------|--------|\n"
        f"| Grok Build | {version('grok')} | `{resolve('grok')}` | `~/.grok/config.toml` |\n"
        f"| Claude Code | {version('claude')} | `{resolve('claude')}` | `~/.claude/settings.json` |\n"
        f"| OpenCode | {version('opencode')} | `{resolve('opencode')}` | `~/.config/opencode/opencode.jsonc` |"
    )


def render(source: str) -> str:
    stamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
    return (
        f"{START}\n"
        f"{table()}\n"
        f"<!-- last refreshed: {stamp} by {source} -->\n"
        f"{END}\n"
    )


def rows_only(text: str) -> str:
    return re.sub(
        r"\n<!-- last refreshed: [^\n]* -->\n" + re.escape(END) + r"\n?$",
        "",
        text,
    )


def main() -> int:
    dest = pathlib.Path(
        os.environ.get(
            "INVENTORY_MD",
            os.path.join(os.environ.get("AGENTS_HOME", str(pathlib.Path.home() / ".agents")), "inventory.local.md"),
        )
    )
    source = re.sub(r"[^A-Za-z0-9._-]", "-", os.environ.get("INVENTORY_SOURCE", "manual"))
    new = render(source)
    if dest.is_file():
        old = dest.read_text()
        if rows_only(old) == rows_only(new):
            print("inventory unchanged")
            return 0
    dest.parent.mkdir(parents=True, exist_ok=True)
    temporary = dest.with_name(f".{dest.name}.tmp.{os.getpid()}")
    temporary.write_text(new)
    temporary.replace(dest)
    print("inventory refreshed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
