#!/usr/bin/env python3
"""Write machine-local CLI versions to inventory.local.md (gitignored).

Live grok/claude/opencode versions differ across machines and must not be
committed into SETUP.md — that made a Ubuntu box fail verify after pulling
Omarchy versions, and the other way around.

Resolution order (must match SETUP.md §1):

1. Login shell (`env -i bash -lc command -v`). This is what mise shims look
   like. `update-apps.sh` mise_managed() uses this probe only, so a leftover
   vendor binary cannot hide a mise-managed tool that is on login PATH.
2. If that is empty: well-known vendor dirs the updater already puts on its
   own PATH (`~/.opencode/bin`, `~/.grok/bin`, `~/.local/bin`). Official
   OpenCode/Grok installers drop bins there and add PATH in `.bashrc`, which
   a non-interactive login shell never sources (interactive-guard). Without
   this step Ubuntu inventory reports OpenCode missing.

Never mutate PATH. Never symlink into `~/.local/bin`. A missing command is
version `unknown` / path `missing` — stderr is never copied into the table.
"""

import datetime
import os
import pathlib
import re
import shlex
import subprocess
import sys

START = "<!-- TOOL_INVENTORY_START -->"
END = "<!-- TOOL_INVENTORY_END -->"
VENDOR_BIN_DIRS = (".opencode/bin", ".grok/bin", ".local/bin")
VERSION_RE = re.compile(r"(\d+\.\d+\.\d+)")
TOOLS = (
    ("Grok Build", "grok", "`~/.grok/config.toml`"),
    ("Claude Code", "claude", "`~/.claude/settings.json`"),
    ("OpenCode", "opencode", "`~/.config/opencode/opencode.jsonc`"),
)


def home_dir() -> pathlib.Path:
    return pathlib.Path(os.environ.get("HOME") or pathlib.Path.home()).expanduser()


def login_shell(cmd: str, home: pathlib.Path) -> subprocess.CompletedProcess:
    # env -i: canonical login resolution, independent of the caller's PATH
    # (boot cron, updater's exported PATH, and AI harnesses all differ).
    try:
        return subprocess.run(
            ["env", "-i", f"HOME={home}", "TERM=dumb", "bash", "-lc", cmd],
            capture_output=True, text=True, timeout=60, check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return subprocess.CompletedProcess(args=[], returncode=1, stdout="", stderr="")


def login_which(binary: str, home: pathlib.Path) -> str:
    result = login_shell(f"command -v -- {shlex.quote(binary)}", home)
    line = (result.stdout or "").strip().splitlines()
    if not line:
        return ""
    path = os.path.normpath(line[0])
    return path if path else ""


def vendor_which(binary: str, home: pathlib.Path) -> str:
    for relative in VENDOR_BIN_DIRS:
        candidate = home / relative / binary
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return str(candidate)
    return ""


def resolve(binary: str, home: pathlib.Path | None = None) -> str:
    home = home or home_dir()
    return login_which(binary, home) or vendor_which(binary, home)


def display_path(path: str, home: pathlib.Path | None = None) -> str:
    if not path:
        return "missing"
    home = home or home_dir()
    home_s = str(home)
    if path == home_s or path.startswith(home_s + os.sep):
        return "~" + path[len(home_s):]
    return path


def parse_version(text: str) -> str:
    match = VERSION_RE.search(text or "")
    return match.group(1) if match else ""


def version(binary: str, path: str = "", home: pathlib.Path | None = None) -> str:
    home = home or home_dir()
    path = path or resolve(binary, home)
    if not path:
        return "unknown"
    result = login_shell(f"{shlex.quote(path)} --version", home)
    found = parse_version(result.stdout or "")
    if found:
        return found
    # Some CLIs print --version on stderr. Only accept a real x.y.z, never
    # "command not found" or other shell noise.
    found = parse_version(result.stderr or "")
    return found if found else "unknown"


def table(home: pathlib.Path | None = None) -> str:
    home = home or home_dir()
    rows = [
        "| Tool | Version | Binary | Config |",
        "|------|---------|--------|--------|",
    ]
    for label, binary, config in TOOLS:
        path = resolve(binary, home)
        rows.append(
            f"| {label} | {version(binary, path, home)} | `{display_path(path, home)}` | {config} |"
        )
    return "\n".join(rows)


def render(source: str, home: pathlib.Path | None = None) -> str:
    stamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
    return (
        f"{START}\n"
        f"{table(home)}\n"
        f"<!-- last refreshed: {stamp} by {source} -->\n"
        f"{END}\n"
    )


def rows_only(text: str) -> str:
    return re.sub(
        r"\n<!-- last refreshed: [^\n]* -->\n" + re.escape(END) + r"\n?$",
        "",
        text,
    )


def _write_exec(path: pathlib.Path, body: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(body)
    path.chmod(0o755)


def _fail(message: str) -> int:
    print(f"self-test FAIL: {message}", file=sys.stderr)
    return 1


def self_test() -> int:
    import tempfile

    with tempfile.TemporaryDirectory() as tmp:
        home = pathlib.Path(tmp)

        path = resolve("opencode", home)
        ver = version("opencode", path, home)
        rendered = table(home)
        if path or ver != "unknown":
            return _fail(f"empty home should be missing/unknown, got path={path!r} ver={ver!r}")
        if "command not" in rendered.lower() or "bash:" in rendered.lower():
            return _fail(f"stderr leaked into table:\n{rendered}")
        if "| OpenCode | unknown | `missing` |" not in rendered:
            return _fail(f"missing row malformed:\n{rendered}")

        vendor = home / ".opencode" / "bin" / "opencode"
        _write_exec(vendor, "#!/bin/sh\necho opencode 9.8.7\n")
        path = resolve("opencode", home)
        ver = version("opencode", path, home)
        if path != str(vendor) or ver != "9.8.7":
            return _fail(f"vendor fallback missed, path={path!r} ver={ver!r}")
        if display_path(path, home) != "~/.opencode/bin/opencode":
            return _fail(f"display_path {display_path(path, home)!r}")

        bindir = home / "bin"
        winner = bindir / "opencode"
        _write_exec(winner, "#!/bin/sh\necho opencode 1.2.3\n")
        (home / ".profile").write_text('PATH="$HOME/bin:$PATH"\nexport PATH\n')
        path = resolve("opencode", home)
        ver = version("opencode", path, home)
        if path != str(winner) or ver != "1.2.3":
            return _fail(f"login PATH must win over vendor dir, path={path!r} ver={ver!r}")

        noisy = home / ".grok" / "bin" / "grok"
        _write_exec(
            noisy,
            "#!/bin/sh\necho 'bash: line 1: grok: command not found' >&2\nexit 127\n",
        )
        # Hide login PATH grok if any; vendor_which still finds this file.
        grok_path = vendor_which("grok", home)
        grok_ver = version("grok", grok_path, home)
        if grok_path != str(noisy) or grok_ver != "unknown":
            return _fail(f"stderr noise must not become a version, path={grok_path!r} ver={grok_ver!r}")

        stderr_ver = home / ".local" / "bin" / "claude"
        _write_exec(stderr_ver, "#!/bin/sh\necho 'claude 4.5.0' >&2\n")
        claude_path = vendor_which("claude", home)
        claude_ver = version("claude", claude_path, home)
        if claude_path != str(stderr_ver) or claude_ver != "4.5.0":
            return _fail(f"stderr x.y.z should count, path={claude_path!r} ver={claude_ver!r}")

    print("self-test ok")
    return 0


def main() -> int:
    if len(sys.argv) > 1 and sys.argv[1] == "--self-test":
        return self_test()

    dest = pathlib.Path(
        os.environ.get(
            "INVENTORY_MD",
            os.path.join(os.environ.get("AGENTS_HOME", str(home_dir() / ".agents")), "inventory.local.md"),
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
