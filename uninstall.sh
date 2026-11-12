#!/usr/bin/env bash
# uninstall.sh — take out what setup.sh put on this machine.
#
#   bash ~/.agents/uninstall.sh                     # print the plan, change nothing
#   bash ~/.agents/uninstall.sh --yes               # do it
#   bash ~/.agents/uninstall.sh --yes --restore-configs
#
# Removed with --yes, and only when the thing is still ours:
#   the four rules symlinks, the generated Cursor rule, the local-override rules,
#   the Claude skill links, the two Claude hook entries, the guard and updater
#   schedule (systemd user units or crontab lines), the installed script copies
#   under ~/cron-jobs, the boot-dashboard autostart entry, the 1config command
#   link, and git's gpg.program when it points at hooks/gpg-git.sh.
#
# Left in place, and named at the end, because a tool or a person may have
# changed them since: the permission lists and modes in the three tool configs
# (--restore-configs puts back the oldest copy setup.sh saved, after saving the
# current one), the Grok memory and compat switches, the Omarchy bar plugin,
# logs and flags under ~/cron-jobs, the machine-notes clone, the keyring, and
# this checkout with its backups.
#
# A plan is the default because an uninstall typed by mistake should cost nothing.
set -uo pipefail

AGENTS_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
export AGENTS_HOME
CANON="$AGENTS_HOME/AGENTS.md"
# Where a config is copied before this script changes it. The override is for verify.sh only.
KEEP_ROOT="${UNINSTALL_BACKUP_DIR:-$AGENTS_HOME/backups}"
DO=0
RESTORE=0
for arg in "$@"; do
  case "$arg" in
    --yes)             DO=1 ;;
    --dry-run)         DO=0 ;;
    --restore-configs) RESTORE=1 ;;
    -h|--help)         sed -n '2,24p' "$0"; exit 0 ;;
    *) echo "uninstall.sh: unknown argument: $arg" >&2; exit 2 ;;
  esac
done

n=0
say() { echo "  $*"; }
# act DESCRIPTION COMMAND...  — print it; run it only with --yes.
act() {
  local what="$1"
  shift
  n=$((n + 1))
  if [ "$DO" = 1 ]; then
    if "$@"; then say "removed  $what"; else say "FAILED   $what"; fi
  else
    say "would remove  $what"
  fi
}

echo "== 1config uninstall — $([ "$DO" = 1 ] && echo "removing" || echo "plan only, nothing changes (add --yes)") =="

echo "[rules]"
for link in "$HOME/.grok/AGENTS.md" "$HOME/.config/opencode/AGENTS.md" "$HOME/.claude/CLAUDE.md" "$HOME/.cursor/AGENTS.md"; do
  if [ -L "$link" ] && [ "$(readlink -f "$link")" = "$CANON" ]; then
    act "$link (symlink to the canonical rules)" rm -f "$link"
  fi
done
rule="$HOME/.cursor/rules/1config.mdc"
if [ -f "$rule" ] && sed -n '2p' "$rule" | grep -q '^description: 1config global rules (generated'; then
  act "$rule (generated Cursor rule)" rm -f "$rule"
fi
if [ -f "$AGENTS_HOME/hooks/local-rules.py" ] \
   && ! python3 "$AGENTS_HOME/hooks/local-rules.py" check --local-json "$AGENTS_HOME/.no-local-json" >/dev/null 2>&1; then
  act "the 1config-local override rules in the four tools" \
    python3 "$AGENTS_HOME/hooks/local-rules.py" apply --local-json "$AGENTS_HOME/.no-local-json"
fi

echo "[claude]"
for dst in "$HOME"/.claude/skills/*; do
  [ -L "$dst" ] || continue
  case "$(readlink -f "$dst")" in
    "$AGENTS_HOME"/skills/*) act "$dst (skill link)" rm -f "$dst" ;;
  esac
done
settings="$HOME/.claude/settings.json"
drop_claude_hooks() {
  local mode="$1"
  SETTINGS="$settings" MODE="$mode" BACKUP="$KEEP_ROOT/uninstall-$(date +%Y%m%d-%H%M%S)" python3 - <<'PY'
import json, os, pathlib, sys
p = pathlib.Path(os.environ["SETTINGS"])
cfg = json.loads(p.read_text())
hooks = cfg.get("hooks", {})
found = 0
for event in ("SessionStart", "PreToolUse"):
    groups = []
    for g in hooks.get(event, []):
        kept = [h for h in g.get("hooks", [])
                if "load-project-agents.sh" not in h.get("command", "")
                and "heredoc-rewrite" not in h.get("command", "")]
        found += len(g.get("hooks", [])) - len(kept)
        if kept:
            groups.append({**g, "hooks": kept})
    if event in hooks:
        if groups:
            hooks[event] = groups
        else:
            del hooks[event]
if "hooks" in cfg and not cfg["hooks"]:
    del cfg["hooks"]
if os.environ["MODE"] == "count":
    print(found)
    sys.exit(0)
backup = pathlib.Path(os.environ["BACKUP"])
backup.mkdir(parents=True, exist_ok=True)
(backup / "claude-settings.json").write_text(p.read_text())
p.write_text(json.dumps(cfg, indent=2) + "\n")
PY
}
if [ -f "$settings" ] && [ "$(drop_claude_hooks count 2>/dev/null || echo 0)" -gt 0 ]; then
  act "the load-project-agents and heredoc-rewrite hooks in $settings (a copy goes to backups/)" drop_claude_hooks write
fi

echo "[schedule]"
sched="$(bash "$AGENTS_HOME/hooks/scheduler.sh" status 2>/dev/null || echo none)"
if [ "$sched" != "none" ]; then
  act "the guard and updater schedule ($sched); other crontab lines stay" bash "$AGENTS_HOME/hooks/scheduler.sh" remove
fi
for f in \
  "$HOME/cron-jobs/agents-symlink-guard/check-links.sh" \
  "$HOME/cron-jobs/agents-symlink-guard/merge-strays.sh" \
  "$HOME/cron-jobs/claude-memory-guard/check-memory.sh" \
  "$HOME/cron-jobs/ai-terminal-tools-update-on-boot/boot-check.sh" \
  "$HOME/cron-jobs/ai-terminal-tools-update-on-boot/update-apps.sh" \
  "$HOME/cron-jobs/ai-terminal-tools-update-on-boot/on-resume.sh" \
  "$HOME/cron-jobs/ai-terminal-tools-update-on-boot/refresh-inventory.py"; do
  [ -f "$f" ] && act "$f (installed copy)" rm -f "$f"
done

echo "[desktop and shell]"
desk="$HOME/.config/autostart/agents-boot-status.desktop"
[ -f "$desk" ] && act "$desk (boot dashboard autostart)" rm -f "$desk"
cli="$HOME/.local/bin/1config"
if [ -L "$cli" ] && [ "$(readlink -f "$cli")" = "$AGENTS_HOME/bin/1config" ]; then
  act "$cli (command link)" rm -f "$cli"
fi
if [ "$(git config --global --get gpg.program 2>/dev/null || true)" = "$AGENTS_HOME/hooks/gpg-git.sh" ]; then
  act "git config --global gpg.program (back to plain gpg, which may open pinentry)" \
    git config --global --unset gpg.program
fi

# The oldest saved copy of a tool config is the closest thing to "before 1config".
# setup.sh saves a file under one name per step that touches it. Within a run
# the names are tried in the order the steps ran, so the first hit in the
# oldest directory is the earliest copy there is.
oldest() {
  local d name
  for d in "$AGENTS_HOME"/backups/setup-*; do
    for name in "$@"; do
      [ -f "$d/$name" ] && { printf '%s\n' "$d/$name"; return 0; }
    done
  done
  return 1
}
restore_one() {
  local live="$1" src keep
  shift
  src="$(oldest "$@")" || { say "no saved copy of $live — left as it is"; return 0; }
  if [ "$DO" != 1 ]; then
    say "would restore  $live  from  $src"
    return 0
  fi
  keep="$KEEP_ROOT/uninstall-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$keep"
  [ -f "$live" ] && cp -p "$live" "$keep/$(basename "$live")"
  cp -p "$src" "$live" && say "restored $live  from  $src  (current copy saved in $keep)"
}
echo "[tool configs]"
if [ "$RESTORE" = 1 ]; then
  restore_one "$HOME/.claude/settings.json" claude-settings.json claude-settings-perms.json claude-settings-heredoc.json
  restore_one "$HOME/.grok/config.toml" config.toml grok-config-perms.toml
  restore_one "$HOME/.config/opencode/opencode.jsonc" opencode-perms.jsonc
else
  say "left as they are (re-run with --restore-configs to put back the oldest saved copies):"
  say "  ~/.claude/settings.json            permissions.allow / ask / deny and defaultMode"
  say "  ~/.grok/config.toml                [permission], [ui] permission_mode, [memory], [compat.claude]"
  say "  ~/.config/opencode/opencode.jsonc  permission.bash / edit / external_directory"
  say "  while they stay, these tools keep running Bash without a prompt if setup.sh turned that on."
fi

echo "[left in place]"
say "$AGENTS_HOME (this checkout, with backups/)"
[ -d "$HOME/.config/omarchy/plugins/firstintegral.1config" ] \
  && say "~/.config/omarchy/plugins/firstintegral.1config and its id in ~/.config/omarchy/shell.json"
[ -d "$HOME/cron-jobs" ] && say "logs and flags under ~/cron-jobs/"
[ -e "$HOME/.local/share/machine-notes/.git" ] && say "~/.local/share/machine-notes (private notes clone)"
[ -f /usr/lib/systemd/system-sleep/ai-terminal-tools-update-resume.sh ] \
  && say "/usr/lib/systemd/system-sleep/ai-terminal-tools-update-resume.sh (root; remove with sudo rm)"
say "the gpg-signing keyring collection and GitHub's web-flow public key"

echo
if [ "$DO" = 1 ]; then
  echo "== done. $n item(s) processed. Install again with: bash $AGENTS_HOME/setup.sh =="
else
  echo "== plan only. $n item(s) would be removed. Run with --yes to remove them. =="
fi
