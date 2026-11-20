#!/usr/bin/env bash
# link-rules.sh — point the four tool rules paths at the canonical AGENTS.md.
#
#   bash ~/.agents/hooks/link-rules.sh <canonical AGENTS.md> <backup dir>
#
# setup.sh step 1 calls this. A real file at one of the four paths is somebody's
# own rules: it is copied into the backup dir first, under a name that says which
# tool it came from, and the link is made only after that copy exists. Three of
# the four paths end in AGENTS.md, so the tool is part of the name:
#   ~/.grok/AGENTS.md              -> rules-grok-AGENTS.md
#   ~/.config/opencode/AGENTS.md   -> rules-config-opencode-AGENTS.md
#   ~/.claude/CLAUDE.md            -> rules-claude-CLAUDE.md
#   ~/.cursor/AGENTS.md            -> rules-cursor-AGENTS.md
# uninstall.sh --restore-configs reads those names. Exit 1 when a copy fails;
# that path is then left as it was.
set -uo pipefail

CANON="${1:?usage: link-rules.sh <canonical AGENTS.md> <backup dir>}"
BACKUP_DIR="${2:?usage: link-rules.sh <canonical AGENTS.md> <backup dir>}"
[ -f "$CANON" ] || { echo "link-rules: $CANON is not a file" >&2; exit 1; }

# The name a saved rules file gets. uninstall.sh derives the same name.
rules_backup_name() {
  local rel="${1#"$HOME"/}"
  rel="${rel#.}"
  printf 'rules-%s\n' "$(printf '%s' "$rel" | tr '/' '-')"
}

rc=0
for link in "$HOME/.grok/AGENTS.md" "$HOME/.config/opencode/AGENTS.md" "$HOME/.claude/CLAUDE.md" "$HOME/.cursor/AGENTS.md"; do
  mkdir -p "$(dirname "$link")"
  if [ -L "$link" ] && [ "$(readlink -f "$link")" = "$(readlink -f "$CANON")" ]; then
    echo "  ok       $link (already linked)"
    continue
  fi
  if [ -e "$link" ] && [ ! -L "$link" ]; then
    saved="$BACKUP_DIR/$(rules_backup_name "$link")"
    mkdir -p "$BACKUP_DIR"
    if cp -p "$link" "$saved" && cmp -s "$link" "$saved"; then
      echo "  backed up existing $link → $saved"
    else
      echo "  FAILED   could not save $link to $saved — left as it is" >&2
      rc=1
      continue
    fi
  fi
  ln -sfn "$CANON" "$link"
  echo "  linked   $link"
done
exit "$rc"
