#!/usr/bin/env python3
"""Refresh SETUP.md tool versions only when the exact inventory rows change."""

import datetime
import os
import pathlib
import re
import subprocess
import sys


START = "<!-- TOOL_INVENTORY_START -->"
END = "<!-- TOOL_INVENTORY_END -->"


def version(binary: str) -> str:
    try:
        result = subprocess.run(
            [binary, "--version"], capture_output=True, text=True, timeout=15, check=False
        )
        lines = (result.stdout or result.stderr or "").strip().splitlines()
        value = lines[0] if lines else "unknown"
    except (OSError, subprocess.SubprocessError):
        value = "unknown"
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
        f"| Grok Build | {version('grok')} | `~/.grok/bin/grok` | `~/.grok/config.toml` |\n"
        f"| Claude Code | {version('claude')} | `~/.local/bin/claude` | `~/.claude/settings.json` |\n"
        f"| OpenCode | {version('opencode')} | `~/.opencode/bin/opencode` | `~/.config/opencode/opencode.jsonc` |"
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
