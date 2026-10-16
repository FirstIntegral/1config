#!/usr/bin/env bash
# Print one OpenCode skill-list JSON document on stdout.
#
# OpenCode 2.x: `opencode api skill.list --standalone`.
# OpenCode 1.x has no `api` command. It prints the top-level help on stderr
# (`Commands:`) and exits 1. Only that shape falls back to `opencode debug skill`.
# A 2.x failure stays a failure: no command list, or a list that still names
# `api`. Exit status is the command that applied. Stdout is its JSON, or
# empty when that command failed.
set -euo pipefail

out="$(mktemp)"
err="$(mktemp)"
cleanup() { rm -f "$out" "$err"; }
trap cleanup EXIT

rc=0
(cd /tmp && timeout 40 opencode api skill.list --standalone >"$out" 2>"$err") || rc=$?
if [ "$rc" -ne 0 ] && grep -q 'Commands:' "$err" && ! grep -qE 'opencode api([[:space:]]|$)' "$err"; then
  rc=0
  : >"$out"
  (cd /tmp && timeout 40 opencode debug skill >"$out" 2>"$err") || rc=$?
fi
cat "$out"
exit "$rc"
