#!/usr/bin/env bash
# Print one OpenCode skill-list JSON document on stdout.
#
# OpenCode 2.x: `opencode api skill.list --standalone`.
# OpenCode 1.x has no `api` command. It prints the top-level help on stderr
# (`Commands:`) and exits 1. Only that shape falls back to `opencode debug skill`.
# A 2.x failure stays a failure: no command list, or a list that still names
# `api`. Exit status is the command that applied. Stdout is its JSON, or
# empty when that command failed.
#
# A 2.x private server can answer `"data":[]` while the background service
# lists every skill (seen on 2.2.7). When the private list is empty and a
# background service is already running, the service is asked instead. A check
# must not start a daemon, so a machine with no service keeps the empty list
# and verify.sh reports it as INFO.
set -euo pipefail

out="$(mktemp)"
err="$(mktemp)"
svc="$(mktemp)"
cleanup() { rm -f "$out" "$err" "$svc"; }
trap cleanup EXIT

is_empty_list() {
  # Small files only reach the grep; a real list never contains this string.
  [ -s "$1" ] && [ "$(tr -d '[:space:]' <"$1" | grep -c '"data":\[\]' || true)" -gt 0 ]
}

rc=0
(cd /tmp && timeout 40 opencode api skill.list --standalone >"$out" 2>"$err") || rc=$?
if [ "$rc" -ne 0 ] && grep -q 'Commands:' "$err" && ! grep -qE 'opencode api([[:space:]]|$)' "$err"; then
  rc=0
  : >"$out"
  (cd /tmp && timeout 40 opencode debug skill >"$out" 2>"$err") || rc=$?
elif [ "$rc" -eq 0 ] && is_empty_list "$out" \
     && pgrep -u "$(id -u)" -f -- 'serve --service' >/dev/null 2>&1; then
  if (cd /tmp && timeout 40 opencode api skill.list >"$svc" 2>/dev/null) \
     && [ -s "$svc" ] && ! is_empty_list "$svc"; then
    cat "$svc" >"$out"
  fi
fi
cat "$out"
exit "$rc"
