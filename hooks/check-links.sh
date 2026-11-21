#!/usr/bin/env bash
# agents-symlink-guard — keeps the unified AGENTS.md symlinks healthy.
# Self-heals with zero information loss:
#   1. stray identical to canonical        -> re-link
#   2. stray differs (any divergence)      -> copy to backups/strays/, check the
#                                             copy, re-link, raise NEEDS-SYMLINK-MERGE
#   3. the copy fails                      -> leave the file where it is
#
# A stray is never merged into the canonical file by a script or a model: every
# tool obeys that file, so what goes into it is a person's decision. The stray
# waits. The flag lists it, the boot dashboard shows it, and an agent says so at
# session start. The person reads the stray, copies what they want, and deletes
# the stray file. This guard then drops its line, and the flag with the last line.
#
# Exit 0 healthy · 2 a stray waits for a person · 1 something could not be done.
# flock-serialized: cron @reboot and boot dashboard may both fire at login.
# Env overrides (CANON, LINKS, GUARD_DIR, STRAYS_DIR) exist for sandbox testing.
set -u

CANON="${CANON:-$HOME/.agents/AGENTS.md}"
LINKS="${LINKS:-$HOME/.grok/AGENTS.md $HOME/.config/opencode/AGENTS.md $HOME/.claude/CLAUDE.md $HOME/.cursor/AGENTS.md}"
DIR="${GUARD_DIR:-$HOME/cron-jobs/agents-symlink-guard}"
LOG="$DIR/check-links.log"
FLAG="$DIR/NEEDS-SYMLINK-MERGE"
STRAYS="${STRAYS_DIR:-$HOME/.agents/backups/strays}"
TS="$(date +%Y%m%d-%H%M%S)"

mkdir -p "$DIR"
mkdir -p "$STRAYS" 2>/dev/null || true
log() { echo "[$TS] $*" >> "$LOG"; }

exec 9>"$DIR/.lock"
flock 9

# Cap the log at its last 2000 lines once it passes 4000. It only ever grew.
if [ -f "$LOG" ] && [ "$(wc -l < "$LOG")" -gt 4000 ]; then
  tail -n 2000 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
fi

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
      # The copy is the only other copy of a person's file. The link replaces
      # the original only after the copy is there and has the same bytes.
      if cp -p "$link" "$stray" 2>/dev/null && cmp -s "$link" "$stray"; then
        ln -sf "$CANON" "$link"
        echo "$stray" >> "$FLAG"
        log "CONFLICT $link (diverged; kept as $stray; link restored — read it, merge by hand what you want, then delete it)"
      else
        rm -f "$stray" 2>/dev/null
        log "ERROR    could not copy $link to $STRAYS — file left in place, link NOT restored"
        status=1
      fi
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

# Keep the flag true: a line whose stray file is gone is done. An empty flag goes.
if [ -f "$FLAG" ]; then
  tmp_flag="$(mktemp)"
  while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] && [ -f "$line" ] && printf '%s\n' "$line"
  done < "$FLAG" | awk '!seen[$0]++' > "$tmp_flag"
  if [ -s "$tmp_flag" ]; then
    mv "$tmp_flag" "$FLAG"
    log "PENDING  $(wc -l < "$FLAG") stray rules file(s) wait for a person (listed in $FLAG)"
    [ "$status" -eq 0 ] && status=2
  else
    rm -f "$tmp_flag" "$FLAG"
    log "CLEARED  no stray is left; flag removed"
  fi
fi

exit "$status"
