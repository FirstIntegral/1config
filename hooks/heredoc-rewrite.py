#!/usr/bin/env python3
# heredoc-rewrite.py — logic half of the PreToolUse heredoc-rewrite hook.
#
# Reads the Claude Code hook payload from stdin. If the Bash command contains
# exactly one QUOTED heredoc and it belongs to the rewrite class
# (python3 - / python - / cat >> X / cat > X), the body is written to a
# scratchpad file under ~/.cache/agents-heredoc/ and the command is rewritten
# to run that file. The hook returns the rewritten command as
# hookSpecificOutput.updatedInput and makes NO permission decision. Every other
# command produces no output, so the normal permission flow applies.
#
# Why no decision: Claude Code evaluates its permission rules against the input
# a hook returns. The rewritten command has no heredoc, so the parse verdict
# that no allow rule could silence is gone, and `python3 <file>` is what the
# allowlist already covers. Whatever stood before or after the heredoc is
# still judged by those rules, segment by segment. An "allow" here would have
# approved that surrounding text too, which is not this hook's to give.
#
# Output shape (Claude Code hooks reference, PreToolUse decision control):
#   {"hookSpecificOutput": {"hookEventName": "PreToolUse", "updatedInput": {...}}}
# updatedInput replaces the whole tool input, so every field is carried over.
import json
import pathlib
import re
import sys
import time
import uuid

CACHE = pathlib.Path.home() / ".cache" / "agents-heredoc"

# io.py TARGET BODY MODE — MODE is "a" (cat >>) or "w" (cat >).
IO_PY = (
    "import sys\n"
    "with open(sys.argv[2], encoding='utf-8') as src:\n"
    "    data = src.read()\n"
    "with open(sys.argv[1], sys.argv[3], encoding='utf-8') as dst:\n"
    "    dst.write(data)\n"
)


def main() -> None:
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return
    tool = payload.get("tool_name", "")
    tin = payload.get("tool_input") or {}
    cmd = tin.get("command", "") if isinstance(tin, dict) else ""
    if tool != "Bash" or not isinstance(cmd, str) or cmd.count("<<'") != 1:
        return
    m = re.search(r"<<'([A-Za-z_][A-Za-z0-9_]*)'", cmd)
    if not m:
        return
    delim = m.group(1)
    body_start = m.end() + 1  # skip the newline after <<'DELIM'
    idx = cmd.find("\n" + delim + "\n", body_start)
    if idx == -1:
        idx = cmd.find("\n" + delim, body_start)
        if idx == -1 or cmd[idx + 1 + len(delim):] != "":
            return  # unterminated or unusual close — leave to normal flow
    # A heredoc hands the command every body line with its newline, the last one too.
    body = cmd[body_start:idx] + "\n"
    suffix = cmd[idx + 1 + len(delim):]
    if len(body) > 200_000:
        return
    prefix = cmd[:m.start()]
    pre = None
    kind = None
    target = None
    pm = re.match(r"(?s)^(?P<pre>.*?)python3? -\s*$", prefix)
    if pm:
        pre, kind = pm.group("pre"), "py"
    else:
        pm = re.match(
            r"(?s)^(?P<pre>.*?)cat >> (?P<target>([^\s']+|'[^']*'))\s*$", prefix
        )
        if pm:
            pre, kind, target = pm.group("pre"), "append", pm.group("target")
        else:
            pm = re.match(
                r"(?s)^(?P<pre>.*?)cat > (?P<target>([^\s']+|'[^']*'))\s*$", prefix
            )
            if pm:
                pre, kind, target = pm.group("pre"), "overwrite", pm.group("target")
    if pre is None:
        return
    d = CACHE / uuid.uuid4().hex[:12]
    d.mkdir(parents=True, exist_ok=True)
    if kind == "py":
        (d / "s.py").write_text(body)
        new = f"{pre}python3 {d / 's.py'}{suffix}"
    else:
        (d / "body").write_text(body)
        (d / "io.py").write_text(IO_PY)
        new = (
            f"{pre}python3 {d / 'io.py'} {target} {d / 'body'} "
            f"{'a' if kind == 'append' else 'w'}{suffix}"
        )
    _cleanup()
    updated = dict(tin)
    updated["command"] = new
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "updatedInput": updated,
        }
    }))


def _cleanup() -> None:
    try:
        now = time.time()
        for child in CACHE.glob("*/*"):
            if now - child.stat().st_mtime > 7 * 86400:
                child.unlink(missing_ok=True)
        for child in CACHE.iterdir():
            try:
                child.rmdir()
            except OSError:
                pass
    except Exception:
        pass


if __name__ == "__main__":
    main()
