#!/usr/bin/env bash
# updater-test.sh — fixtures for the tool updater and the crontab fallback.
#
#   bash hooks/updater-test.sh
#
# updater/update-apps.sh runs to the end in a scratch home where opencode, grok,
# and curl are stubs that record what they were given. hooks/scheduler.sh runs
# against a stub crontab. One line per case: `ok <what>` or `FAIL <what>`. Exit 1
# when any case fails. verify.sh replays the lines. No network, no real tool.
set -uo pipefail

HOOKS="$(cd "$(dirname "$0")" && pwd -P)"
ROOT="$(cd "$HOOKS/.." && pwd -P)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

fails=0
pass() { echo "ok $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }

# --- update-apps.sh: what a tool's own updater inherits -------------------------
h="$T/home"
mkdir -p "$h/.opencode/bin" "$h/.grok/bin" "$h/.local/bin" "$h/upd"
# curl: GitHub answers 200 to everything, with no body.
printf '#!/bin/sh\nfor a in "$@"; do [ "$a" = "%%{http_code}" ] && { printf 200; exit 0; }; done\nexit 0\n' > "$h/.local/bin/curl"
cat > "$h/.opencode/bin/opencode" <<'STUB'
#!/bin/sh
case "$1" in
  --version) echo 1.0.0 ;;
  upgrade) env > "$HOME/opencode.env" ;;
esac
STUB
cat > "$h/.grok/bin/grok" <<'STUB'
#!/bin/sh
case "$1" in
  --version) echo 1.0.0 ;;
  update)
    env > "$HOME/grok.env"
    ls -l /proc/$$/fd > "$HOME/grok.fds" 2>/dev/null
    ;;
esac
STUB
chmod +x "$h/.local/bin/curl" "$h/.opencode/bin/opencode" "$h/.grok/bin/grok"
# The token is assembled here so this file never holds a token-shaped string.
tok="fixture-$(printf 'tok%.0s' 1 2 3)"
env -i HOME="$h" PATH=/usr/bin:/bin UPD_INSTALL_DIR="$h/upd" AGENTS_HOME="$h/brain" \
  GITHUB_TOKEN="$tok" GH_TOKEN="$tok" TIMEOUT_DEFAULT=20 \
  bash "$ROOT/updater/update-apps.sh" >/dev/null 2>&1
if [ -f "$h/grok.env" ] && [ -f "$h/opencode.env" ]; then
  if grep -q "^GITHUB_TOKEN=$tok\$" "$h/opencode.env"; then
    pass "updater: opencode upgrade is given the GitHub token it needs"
  else
    fail "updater: opencode upgrade did not get the GitHub token"
  fi
  if ! grep -q "$tok" "$h/grok.env"; then
    pass "updater: grok update does not inherit the GitHub token"
  else
    fail "updater: grok update inherited the GitHub token ($(grep -c "$tok" "$h/grok.env") variable(s))"
  fi
  # Only this run's own lock counts: setup.sh and sync.sh hold the real one
  # around everything they start, this fixture included.
  if ! grep -qF "$h/upd/.update.lock" "$h/grok.fds"; then
    pass "updater: a tool's updater does not inherit the run lock"
  else
    fail "updater: grok update holds the run lock's file descriptor, so a child it leaves behind keeps the lock"
  fi
else
  fail "updater: the fixture run did not reach both tool updates ($(tail -n 3 "$h/upd/update-apps.log" 2>/dev/null | tr '\n' ' '))"
fi

# --- scheduler.sh: the person's own crontab lines stay as they are --------------
s="$T/sched"
mkdir -p "$s/bin" "$s/home"
cat > "$s/bin/crontab" <<'STUB'
#!/bin/sh
f="$STUB_DIR/crontab.txt"
case "$1" in
  -l) [ -f "$f" ] && cat "$f" || { echo "no crontab for user" >&2; exit 1; } ;;
  -r) rm -f "$f" ;;
  -)  cat > "$f" ;;
  *)  exit 2 ;;
esac
STUB
printf '#!/bin/sh\nexit 1\n' > "$s/bin/systemctl"
chmod +x "$s/bin/crontab" "$s/bin/systemctl"
sched() {
  env -u XDG_CONFIG_HOME -u AGENTS_SCHEDULER -u SCHEDULER_UNIT_DIR HOME="$s/home" AGENTS_HOME="$ROOT" \
    STUB_DIR="$s" PATH="$s/bin:/usr/bin:/bin" bash "$HOOKS/scheduler.sh" "$@" >/dev/null 2>&1
}
mine="$(printf '# backups\n0 3 * * * /usr/local/bin/backup\n\n# mail\n\n15 * * * * /usr/local/bin/fetch-mail')"
printf '%s\n' "$mine" > "$s/crontab.txt"
sched install auto
kept="$(grep -v 'cron-jobs/' "$s/crontab.txt")"
if [ "$kept" = "$mine" ] && grep -q 'check-links.sh' "$s/crontab.txt"; then
  pass "scheduler: installing the cron lines keeps the person's blank lines and comments"
else
  fail "scheduler: installing the cron lines rewrote the person's own crontab lines"
fi
sched remove
if [ "$(cat "$s/crontab.txt" 2>/dev/null)" = "$mine" ]; then
  pass "scheduler: removing the cron lines gives the person's crontab back byte for byte"
else
  fail "scheduler: removing the cron lines did not give the person's crontab back"
fi

[ "$fails" -eq 0 ]
