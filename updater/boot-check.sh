#!/usr/bin/env bash
# Boot / resume update gate.
# Waits for internet (backoff 0/1/3/5/10/15 min), then runs update-apps.sh.
# Triggered by @reboot cron and by systemd-sleep resume hook.
# SOURCE: ~/.agents/updater/ — setup.sh copies to ~/cron-jobs/ai-terminal-tools-update-on-boot/
set -u

DIR="${UPD_INSTALL_DIR:-$HOME/cron-jobs/ai-terminal-tools-update-on-boot}"
LOG="$DIR/update-apps.log"
LOCK="$DIR/.update.lock"
UPDATE="$DIR/update-apps.sh"
ts() { date '+%Y-%m-%d %H:%M:%S'; }

export PATH="$HOME/.opencode/bin:$HOME/.grok/bin:$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"

# Backoff schedule in seconds: 0s (immediate), then 1, 3, 5, 10, 15 min
DELAYS=(0 60 180 300 600 900)

net_up() {
  # Light probe only — full github.com HTML is large and often times out on
  # slow/boot paths even when the net is fine.
  #
  # NEVER hit api.github.com here: unauthenticated GETs burn the 60/hr rate
  # limit and then opencode upgrade fails with 403. HEAD github.com (HTML CDN)
  # does not count against the REST quota; cloudflare is a pure connectivity fallback.
  curl -fsS --max-time 10 -o /dev/null -I https://github.com 2>/dev/null \
    || curl -fsS --max-time 10 -o /dev/null -I https://www.cloudflare.com 2>/dev/null
}

echo "[$(ts)] boot-check START (trigger at $(date '+%H:%M'))" >> "$LOG"

got_net=0
for i in "${!DELAYS[@]}"; do
  wait="${DELAYS[$i]}"
  [ "$wait" -gt 0 ] && { echo "[$(ts)] waiting ${wait}s before attempt $((i+1))/${#DELAYS[@]}" >> "$LOG"; sleep "$wait"; }
  if net_up; then
    got_net=1
    echo "[$(ts)] net UP on attempt $((i+1))" >> "$LOG"
    break
  fi
  echo "[$(ts)] no net (attempt $((i+1))/${#DELAYS[@]})" >> "$LOG"
done

if [ "$got_net" -ne 1 ]; then
  echo "[$(ts)] boot-check: no net after all retries → skip until next boot/resume" >> "$LOG"
  exit 0
fi

# Run the updater — it holds its own flock to prevent concurrent boot/resume runs
echo "[$(ts)] boot-check: handing off to update-apps.sh" >> "$LOG"
"$UPDATE"
rc=$?
echo "[$(ts)] boot-check END (rc=$rc from updater)" >> "$LOG"
exit $rc