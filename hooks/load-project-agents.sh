#!/usr/bin/env bash
# load-project-agents.sh — Claude Code SessionStart hook.
# Injects the nearest project AGENTS.md into context so Claude Code gets
# project rules the same way Grok/OpenCode do (they read AGENTS.md natively).
# Walks up from cwd; stops before $HOME (global rules already load via
# the ~/.claude/CLAUDE.md symlink). Nearest AGENTS.md wins. Silent if none.
# Oversized files are truncated (AGENTS_CAP bytes) to protect context budget.
set -u

CAP="${AGENTS_CAP:-20480}"
dir="$PWD"
home="$(cd "$HOME" 2>/dev/null && pwd)"
while [ -n "$dir" ] && [ "$dir" != "/" ] && [ "$dir" != "$home" ]; do
  f="$dir/AGENTS.md"
  if [ -f "$f" ]; then
    printf '# Project rules (auto-loaded from %s)\n\n' "$f"
    size="$(stat -c%s "$f" 2>/dev/null || echo 0)"
    if [ "${size:-0}" -gt "$CAP" ]; then
      head -c "$CAP" "$f"
      printf '\n<!-- truncated at %s bytes; full file: %s -->\n' "$CAP" "$f"
    else
      cat "$f"
    fi
    exit 0
  fi
  dir="$(dirname "$dir")"
done
exit 0
