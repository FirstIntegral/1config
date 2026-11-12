#!/usr/bin/env bash
# heredoc-rewrite.sh — Claude Code PreToolUse hook (matcher: Bash).
#
# Rewrites the always-prompt parse-verdict class — quoted-delimiter heredocs
# whose body mixes braces with quotes (Python f-strings) — into scratchpad-file
# invocations. Claude decides these verdicts BEFORE consulting the allowlist,
# so no allow rule can silence them; a hook that rewrites them to
# allowlist-shaped commands can. The hook returns the rewritten command as
# updatedInput and decides nothing: the permission rules then judge it.
#
# Scope is deliberately narrow: only `python3 -` / `python -` / `cat >> X` /
# `cat > X` heredocs with a QUOTED delimiter are rewritten. Unquoted heredocs,
# heredocs under bash/sh/sudo/anything else, and commands without heredocs
# produce no output and keep the normal permission flow (still prompt).
#
# stdin: Claude Code hook payload (JSON). stdout: empty, or
# {"hookSpecificOutput": {"hookEventName": "PreToolUse", "updatedInput": {...}}}.
set -euo pipefail
exec python3 "$HOME/.agents/hooks/heredoc-rewrite.py"
