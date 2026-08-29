#!/usr/bin/env python3
"""Refresh SETUP.md tool versions only when the exact inventory rows change.

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


def main() -> int:
    setup = pathlib.Path(os.environ.get("SETUP_MD", pathlib.Path.home() / ".agents/SETUP.md"))
    source = re.sub(r"[^A-Za-z0-9._-]", "-", os.environ.get("INVENTORY_SOURCE", "manual"))
    if not setup.is_file():
        print(f"missing {setup}", file=sys.stderr)
        return 1

    rows = (
        "| Tool | Version | Binary | Config |\n"
        "|------|---------|--------|--------|\n"
        f"| Grok Build | {version('grok')} | `{resolve('grok')}` | `~/.grok/config.toml` |\n"
        f"| Claude Code | {version('claude')} | `{resolve('claude')}` | `~/.claude/settings.json` |\n"
        f"| OpenCode | {version('opencode')} | `{resolve('opencode')}` | `~/.config/opencode/opencode.jsonc` |"
    )
    text = setup.read_text()
    pattern = re.compile(re.escape(START) + r".*?" + re.escape(END), re.S)
    match = pattern.search(text)
    if not match:
        print(f"inventory markers missing in {setup}", file=sys.stderr)
        return 1

    desired_rows = START + "\n" + rows
    current_rows = re.sub(
        r"\n<!-- last refreshed: [^\n]* -->\n" + re.escape(END) + r"$",
        "",
        match.group(0),
    )
    if current_rows == desired_rows:
        print("inventory unchanged")
        return 0

    stamp = f"<!-- last refreshed: {datetime.datetime.now().strftime('%Y-%m-%d %H:%M')} by {source} -->"
    replacement = desired_rows + "\n" + stamp + "\n" + END
    updated = pattern.sub(replacement, text)
    temporary = setup.with_name(f".{setup.name}.tmp.{os.getpid()}")
    temporary.write_text(updated)
    temporary.replace(setup)
    print("inventory refreshed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
