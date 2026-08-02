#!/usr/bin/env bash
# agents-symlink-guard — keeps the unified AGENTS.md symlinks healthy.
# Self-heals with zero information loss:
#   1. stray identical to canonical        -> re-link
#   2. stray differs (any divergence)      -> quarantine to backups/strays/,
#                                             re-link, raise NEEDS-SYMLINK-MERGE flag
#             (prefix-matched strays are NEVER auto-merged into canonical —
#              appending foreign bytes would pollute the file all tools load)
# flock-serialized: cron @reboot and boot dashboard may both fire at login.
# Env overrides (CANON, LINKS, GUARD_DIR) exist for sandbox testing.
set -u

CANON="${CANON:-$HOME/.agents/AGENTS.md}"
LINKS="${LINKS:-$HOME/.grok/AGENTS.md $HOME/.config/opencode/AGENTS.md $HOME/.claude/CLAUDE.md}"
DIR="${GUARD_DIR:-$HOME/cron-jobs/agents-symlink-guard}"
LOG="$DIR/check-links.log"
FLAG="$DIR/NEEDS-SYMLINK-MERGE"
STRAYS="$HOME/.agents/backups/strays"
TS="$(date +%Y%m%d-%H%M%S)"

mkdir -p "$DIR" "$STRAYS"
log() { echo "[$TS] $*" >> "$LOG"; }

exec 9>"$DIR/.lock"
flock 9

if [ ! -f "$CANON" ]; then
  log "FATAL: canonical $CANON missing — nothing relinked"
  exit 1
fi

status=0
for link in $LINKS; do
  if [ -L "$link" ]; then
    tgt="$(readlink -f "$link")"
    if [ "$tgt" = "$CANON" ]; then
      log "OK       $link"
    else
      ln -sfn "$CANON" "$link" && log "REPOINT  $link (was -> $tgt)" || log "ERROR    relink failed: $link"
    fi
  elif [ -e "$link" ]; then
    if cmp -s "$link" "$CANON"; then
      ln -sf "$CANON" "$link" && log "FIXED    $link (identical copy had replaced link; re-linked, no content change)"
    else
      stray="$STRAYS/$(echo "$link" | tr '/' '_').$TS"
      cp -p "$link" "$stray"
      ln -sf "$CANON" "$link"
      echo "$stray" >> "$FLAG"
      log "CONFLICT $link (diverged; quarantined: $stray; link restored — merge into canonical if needed, then delete $FLAG)"
      status=2
    fi
  else
    ln -s "$CANON" "$link" && log "CREATE   $link (was missing)" || log "ERROR    create failed: $link"
  fi
done

# Migrate legacy flag name if present
if [ -f "$DIR/NEEDS-MERGE" ] && [ ! -f "$FLAG" ]; then
  mv "$DIR/NEEDS-MERGE" "$FLAG"
  log "MIGRATED legacy NEEDS-MERGE -> NEEDS-SYMLINK-MERGE"
elif [ -f "$DIR/NEEDS-MERGE" ]; then
  cat "$DIR/NEEDS-MERGE" >> "$FLAG"
  rm -f "$DIR/NEEDS-MERGE"
  log "MIGRATED merged legacy NEEDS-MERGE into NEEDS-SYMLINK-MERGE"
fi

exit "$status"
