#!/bin/sh
# Root systemd sleep hook. Install once per machine, then reinstall after source changes:
#   sudo install -o root -g root -m 0755 ~/.agents/updater/system-sleep-shim.sh \
#     /usr/lib/systemd/system-sleep/ai-terminal-tools-update-resume.sh
#
# Sleep hooks run as root while user.slice is frozen. Queue a delayed transient
# system service for each logged-in user that has the updater installed; systemd
# then runs the user-owned helper with explicit identity and HOME after resume.
set -u

[ "${1:-}" = "post" ] || exit 0

SYSTEMD_RUN="${SYSTEMD_RUN:-systemd-run}"
LOGINCTL="${LOGINCTL:-loginctl}"
GETENT="${GETENT:-getent}"
DELAY="${AI_UPDATE_DELAY:-10s}"

log() {
  if command -v logger >/dev/null 2>&1; then
    logger -t ai-terminal-tools-update-resume -- "$*"
  else
    printf '%s\n' "$*" >&2
  fi
}

if [ -n "${AI_UPDATE_USERS:-}" ]; then
  users="$AI_UPDATE_USERS"
else
  users="$("$LOGINCTL" list-users --no-legend 2>/dev/null | awk '{print $2}')"
fi

found=0
failed=0
for user in $users; do
  passwd="$("$GETENT" passwd "$user" 2>/dev/null || true)"
  home="$(printf '%s\n' "$passwd" | cut -d: -f6)"
  [ -n "$home" ] || continue
  script="$home/cron-jobs/ai-terminal-tools-update-on-boot/on-resume.sh"
  [ -x "$script" ] || continue
  if [ "$(stat -c '%U' "$script" 2>/dev/null || true)" != "$user" ]; then
    log "refusing $script: owner does not match $user"
    failed=1
    continue
  fi

  found=1
  uid="$(id -u "$user")"
  unit="ai-terminal-tools-update-resume-${uid}-$(date +%s)-$$"
  if "$SYSTEMD_RUN" --quiet --collect \
      --unit="$unit" \
      --description="AI terminal tools update after resume ($user)" \
      --on-active="$DELAY" \
      --uid="$user" \
      --working-directory="$home" \
      --setenv="HOME=$home" \
      --setenv="USER=$user" \
      --setenv="LOGNAME=$user" \
      --setenv="PATH=$home/.opencode/bin:$home/.grok/bin:$home/.local/bin:/usr/local/bin:/usr/bin:/bin" \
      "$script" post "${2:-unknown}"; then
    log "scheduled $unit for $user after $DELAY"
  else
    log "failed to schedule resume updater for $user"
    failed=1
  fi
done

if [ "$found" -eq 0 ]; then
  log "no logged-in user has the resume updater installed"
  exit 1
fi
exit "$failed"
