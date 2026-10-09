#!/usr/bin/env bash
# load-project-agents.sh — Claude Code SessionStart hook.
#
# Claude Code 2.1.277+ reads a project AGENTS.md on its own when instruction
# mode is the default (claude-md-or-agents-md) and no project CLAUDE.md,
# .claude/CLAUDE.md, or CLAUDE.local.md sits in cwd or a parent. The user
# file ~/.claude/CLAUDE.md does not count. Printing the file again would
# load it twice. This hook prints the nearest project AGENTS.md only when
# that native read will not happen:
#   - Claude older than 2.1.277, or version unknown
#   - instruction mode claude-md or managed-only, or an unknown mode
#   - default mode and a suppressing CLAUDE.md is present
# Mode claude-md-and-agents-md already loads AGENTS.md, so this hook is quiet.
# The walk that prints a file still stops before $HOME. Global rules load
# through the ~/.claude/CLAUDE.md symlink.
#
# Tests set AGENTS_CLAUDE_VERSION and AGENTS_INSTRUCTION_MODE (empty mode
# means the default). Unset, the version comes from `claude --version` and
# the mode from managed settings, then ~/.claude/settings.json.
set -u

CAP="${AGENTS_CAP:-20480}"
NATIVE_AT="2.1.277"

home="$(cd "$HOME" 2>/dev/null && pwd)"
user_claude="$home/.claude/CLAUDE.md"

version_at_least() {
  local got="$1" want="$2"
  local -a g w
  local i av bv
  IFS=. read -r -a g <<< "${got%% *}"
  IFS=. read -r -a w <<< "$want"
  for i in 0 1 2; do
    av="${g[$i]:-0}"
    bv="${w[$i]:-0}"
    av="${av//[^0-9]/}"
    bv="${bv//[^0-9]/}"
    av="${av:-0}"
    bv="${bv:-0}"
    if ((10#$av > 10#$bv)); then return 0; fi
    if ((10#$av < 10#$bv)); then return 1; fi
  done
  return 0
}

claude_version() {
  local out
  if [ -n "${AGENTS_CLAUDE_VERSION+x}" ]; then
    printf '%s' "$AGENTS_CLAUDE_VERSION"
    return 0
  fi
  out="$(timeout 2 claude --version 2>/dev/null || true)"
  printf '%s' "${out%% *}"
}

instruction_mode() {
  if [ -n "${AGENTS_INSTRUCTION_MODE+x}" ]; then
    printf '%s' "$AGENTS_INSTRUCTION_MODE"
    return 0
  fi
  python3 - <<'PY'
import json
import pathlib

ids = ("cc-plugin-agents-md@builtin", "agents-md@builtin")
paths = (
    pathlib.Path("/etc/claude-code/managed-settings.json"),
    pathlib.Path("/etc/claude-code/settings.json"),
    pathlib.Path.home() / ".claude" / "settings.json",
)
found = ""
for path in paths:
    if not path.is_file():
        continue
    try:
        data = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        continue
    configs = data.get("pluginConfigs") or {}
    if not isinstance(configs, dict):
        continue
    for plugin_id in ids:
        block = configs.get(plugin_id) or {}
        if not isinstance(block, dict):
            continue
        options = block.get("options") or {}
        if isinstance(options, dict) and options.get("instructionFiles"):
            found = str(options["instructionFiles"])
            break
    if found:
        break
print(found, end="")
PY
}

suppressor_present() {
  local dir="$PWD" rel f
  while [ -n "$dir" ]; do
    for rel in CLAUDE.md .claude/CLAUDE.md CLAUDE.local.md; do
      f="$dir/$rel"
      if [ -e "$f" ] || [ -L "$f" ]; then
        [ "$f" = "$user_claude" ] && continue
        return 0
      fi
    done
    [ "$dir" = "/" ] && break
    dir="$(dirname "$dir")"
  done
  return 1
}

# 0 = Claude will load project AGENTS.md itself. 1 = this hook must print it.
native_loads() {
  local ver mode
  ver="$(claude_version)"
  if ! version_at_least "$ver" "$NATIVE_AT"; then
    return 1
  fi
  mode="$(instruction_mode)"
  case "$mode" in
    claude-md-and-agents-md) return 0 ;;
    ""|claude-md-or-agents-md)
      if suppressor_present; then return 1; else return 0; fi
      ;;
    *) return 1 ;;
  esac
}

inject_nearest() {
  local dir="$PWD" f size
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
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 0
}

if native_loads; then
  exit 0
fi
inject_nearest
exit 0
