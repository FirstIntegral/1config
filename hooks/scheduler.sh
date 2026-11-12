#!/usr/bin/env bash
# scheduler.sh — put the guards and the tool updater on a schedule.
#
#   bash ~/.agents/hooks/scheduler.sh install [auto|timers|cron]   # setup.sh runs `install`
#   bash ~/.agents/hooks/scheduler.sh status                        # timers | cron | both | none
#
# auto (the default, or $AGENTS_SCHEDULER): systemd user units when a user
# manager answers, cron when none does.
#
#   timers  1config-guards.timer   daily with catch-up (Persistent=true), and 2 min after login.
#                                  Its service runs the symlink guard, the stray merge, and the
#                                  memory guard as one ordered chain.
#           1config-updater.service  enabled for default.target: boot-check.sh once per login.
#   cron    the same jobs. The guard chain is one line, so the merge still follows the guard.
#
# Exactly one of the two is left installed, and the other is removed only after
# the chosen one is confirmed. A crontab line that is not ours is never
# touched. A `crontab -l` that fails for any reason other than "no crontab"
# leaves the crontab alone: writing back an empty read would delete the user's jobs.
#
# Exit 0 installed (or nothing to schedule with: a note is printed) · 1 the requested scheduler
# could not be installed · 2 usage. SCHEDULER_UNIT_DIR is for verify.sh only.
set -uo pipefail

AGENTS_HOME="${AGENTS_HOME:-$HOME/.agents}"
GUARD_DIR="$HOME/cron-jobs/agents-symlink-guard"
MEM_GUARD_DIR="$HOME/cron-jobs/claude-memory-guard"
UPD_DIR="$HOME/cron-jobs/ai-terminal-tools-update-on-boot"
UNIT_SRC="$AGENTS_HOME/systemd"
UNIT_DIR="${SCHEDULER_UNIT_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user}"
UNITS="1config-guards.service 1config-guards.timer 1config-updater.service"
ENABLED="1config-guards.timer 1config-updater.service"
OURS='agents-symlink-guard|claude-memory-guard|ai-terminal-tools-update-on-boot'

log() { echo "  $*"; }

have_user_manager() {
  command -v systemctl >/dev/null 2>&1 && systemctl --user daemon-reload >/dev/null 2>&1
}

timers_enabled() {
  local u
  command -v systemctl >/dev/null 2>&1 || return 1
  for u in $ENABLED; do
    [ "$(systemctl --user is-enabled "$u" 2>/dev/null)" = "enabled" ] || return 1
  done
  return 0
}

install_timers() {
  local u
  [ -d "$UNIT_SRC" ] || { log "WARNING: $UNIT_SRC missing — copy ~/.agents fully"; return 1; }
  mkdir -p "$UNIT_DIR" || return 1
  for u in $UNITS; do
    [ -f "$UNIT_SRC/$u" ] || { log "WARNING: systemd/$u missing"; return 1; }
    cmp -s "$UNIT_SRC/$u" "$UNIT_DIR/$u" || cp "$UNIT_SRC/$u" "$UNIT_DIR/$u" || return 1
  done
  systemctl --user daemon-reload >/dev/null 2>&1 || return 1
  # The timer starts now. The updater service is only enabled: it runs at the next login.
  systemctl --user enable --now 1config-guards.timer >/dev/null 2>&1 || return 1
  systemctl --user enable 1config-updater.service >/dev/null 2>&1 || return 1
  timers_enabled
}

remove_timers() {
  local u had=0
  for u in $UNITS; do
    [ -e "$UNIT_DIR/$u" ] && had=1
  done
  [ "$had" = 1 ] || return 0
  if command -v systemctl >/dev/null 2>&1; then
    systemctl --user disable --now 1config-guards.timer >/dev/null 2>&1 || true
    systemctl --user disable 1config-updater.service >/dev/null 2>&1 || true
  fi
  for u in $UNITS; do
    rm -f "$UNIT_DIR/$u"
  done
  command -v systemctl >/dev/null 2>&1 && systemctl --user daemon-reload >/dev/null 2>&1 || true
  log "removed the systemd user units"
}

# cron_read -> CT_OLD holds the current crontab ("" when there is none).
# Returns 1 when the crontab cannot be read: the caller must not write then.
CT_OLD=""
cron_read() {
  local err rc=0
  err="$(mktemp)"
  CT_OLD="$(crontab -l 2>"$err")" || rc=$?
  if [ "$rc" -ne 0 ]; then
    if grep -qi 'no crontab' "$err"; then
      CT_OLD=""
      rc=0
    else
      log "WARNING: crontab -l failed ($(head -n 1 "$err" | cut -c1-80)) — crontab left as it is"
    fi
  fi
  rm -f "$err"
  return "$rc"
}

cron_has_ours() {
  command -v crontab >/dev/null 2>&1 || return 1
  crontab -l 2>/dev/null | grep -qE "$OURS"
}

cron_install() {
  local rest chain
  command -v crontab >/dev/null 2>&1 || return 1
  cron_read || return 1
  rest="$(printf '%s\n' "$CT_OLD" | grep -vE "$OURS" || true)"
  chain="$GUARD_DIR/check-links.sh; $GUARD_DIR/merge-strays.sh; $MEM_GUARD_DIR/check-memory.sh"
  {
    printf '%s\n' "$rest"
    printf '@daily %s\n@reboot %s\n@reboot %s\n' "$chain" "$chain" "$UPD_DIR/boot-check.sh"
  } | grep -v '^$' | crontab - || return 1
  cron_has_ours
}

cron_remove() {
  local rest
  cron_has_ours || return 0
  cron_read || return 1
  rest="$(printf '%s\n' "$CT_OLD" | grep -vE "$OURS" | grep -v '^$' || true)"
  if [ -n "$rest" ]; then
    printf '%s\n' "$rest" | crontab - || return 1
  else
    # Only our lines were there. An empty crontab and no crontab schedule the same.
    crontab -r >/dev/null 2>&1 || return 1
  fi
  log "removed the 1config lines from the crontab (other lines untouched)"
}

status() {
  local t=0 c=0
  timers_enabled && t=1
  cron_has_ours && c=1
  case "$t$c" in
    11) echo both ;;
    10) echo timers ;;
    01) echo cron ;;
    *)  echo none ;;
  esac
}

install() {
  local want="$1"
  case "$want" in
    auto|timers)
      if have_user_manager && install_timers; then
        log "installed 1config-guards.timer (daily, catch-up, after login) + 1config-updater.service (each login)"
        # The old scheduler goes only now that the new one is confirmed.
        cron_remove || log "WARNING: the 1config crontab lines are still there — both schedulers run until they are removed"
        return 0
      fi
      if [ "$want" = timers ]; then
        log "ERROR: systemd user units could not be installed (no user manager?)"
        return 1
      fi
      log "systemd user units are not available here — using cron"
      ;;
    cron) ;;
    *) echo "usage: scheduler.sh install [auto|timers|cron]" >&2; return 2 ;;
  esac
  if ! command -v crontab >/dev/null 2>&1; then
    if [ "$want" = cron ]; then
      log "ERROR: crontab not found"
      return 1
    fi
    log "WARNING: no systemd user manager and no crontab — add these jobs by hand:"
    log "  @daily  $GUARD_DIR/check-links.sh; $GUARD_DIR/merge-strays.sh; $MEM_GUARD_DIR/check-memory.sh"
    log "  @reboot $UPD_DIR/boot-check.sh"
    return 0
  fi
  if cron_install; then
    log "installed crontab: guard chain (@daily + @reboot) + tool updater (@reboot)"
    remove_timers
    return 0
  fi
  log "ERROR: crontab could not be written"
  return 1
}

case "${1:-}" in
  install) install "${2:-${AGENTS_SCHEDULER:-auto}}" ;;
  status)  status ;;
  *) echo "usage: scheduler.sh install [auto|timers|cron] | status" >&2; exit 2 ;;
esac
