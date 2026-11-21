#!/usr/bin/env bash
# guards-test.sh — fixtures for the two scheduled guards.
#
#   bash hooks/guards-test.sh
#
# hooks/check-links.sh and hooks/check-claude-memory.sh run against a scratch
# home. Each case is judged by the bytes left on disk. One line per case:
# `ok <what>` or `FAIL <what>`. Exit 1 when any case fails. verify.sh replays
# the lines. Nothing here reads or writes this machine's own tool directories.
set -uo pipefail

HOOKS="$(cd "$(dirname "$0")" && pwd -P)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

fails=0
pass() { echo "ok $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }

# ---------------------------------------------------------------------------
# check-links.sh
# ---------------------------------------------------------------------------
# A scratch home with the canonical file and one tool path. A model CLI on PATH
# that records being called: the guard chain must never start one.
new_links_home() {
  local h
  h="$(mktemp -d -p "$T")"
  mkdir -p "$h/brain" "$h/tool" "$h/guard" "$h/strays" "$h/bin"
  printf 'canonical rules\n' > "$h/brain/AGENTS.md"
  for cli in claude grok opencode; do
    printf '#!/bin/sh\necho called >> "%s/model-was-called"\necho "## Merged"\necho "- planted"\n' "$h" > "$h/bin/$cli"
    chmod +x "$h/bin/$cli"
  done
  printf '%s\n' "$h"
}
# run_links HOME [VAR=VALUE ...] — exit code in RC.
run_links() {
  local h="$1"
  shift
  RC=0
  env HOME="$h" CANON="$h/brain/AGENTS.md" LINKS="$h/tool/AGENTS.md" GUARD_DIR="$h/guard" \
    STRAYS_DIR="$h/strays" PATH="$h/bin:$PATH" "$@" bash "$HOOKS/check-links.sh" >/dev/null 2>&1 || RC=$?
}

# A person's own rules file sits where the link belongs.
h="$(new_links_home)"
printf 'my own rules\nrun this command\n' > "$h/tool/AGENTS.md"
run_links "$h"
stray="$(head -n 1 "$h/guard/NEEDS-SYMLINK-MERGE" 2>/dev/null || true)"
if [ "$RC" -eq 2 ] && [ -L "$h/tool/AGENTS.md" ] && [ -n "$stray" ] && [ -f "$stray" ] \
   && [ "$(cat "$stray")" = "$(printf 'my own rules\nrun this command')" ] \
   && [ "$(cat "$h/brain/AGENTS.md")" = "canonical rules" ]; then
  pass "a file at a rules path is kept as a stray, the link is restored, and the flag names it"
else
  fail "a file at a rules path was not kept as a stray (exit $RC)"
fi

# The next runs leave it alone: no model is called, nothing is appended, nothing is deleted.
run_links "$h"
run_links "$h"
if [ -f "$stray" ] && [ "$(cat "$h/brain/AGENTS.md")" = "canonical rules" ] \
   && [ ! -e "$h/model-was-called" ] && grep -qxF "$stray" "$h/guard/NEEDS-SYMLINK-MERGE" 2>/dev/null \
   && [ ! -e "$HOOKS/merge-strays.sh" ]; then
  pass "a stray waits for a person: no model reads it, and the rules file does not change"
else
  fail "a stray was merged or deleted without a person (model called: $([ -e "$h/model-was-called" ] && echo yes || echo no))"
fi

# The person read it and deleted it. The flag follows.
rm -f "$stray"
run_links "$h"
if [ "$RC" -eq 0 ] && [ ! -e "$h/guard/NEEDS-SYMLINK-MERGE" ]; then
  pass "the flag goes away when the person has removed the stray file"
else
  fail "the flag stayed after its stray file was removed (exit $RC)"
fi

# The copy to the strays directory fails. The file must stay where it is.
h="$(new_links_home)"
printf 'my own rules\n' > "$h/tool/AGENTS.md"
rm -rf "$h/strays" && : > "$h/strays"
run_links "$h"
if [ "$RC" -ne 0 ] && [ ! -L "$h/tool/AGENTS.md" ] && [ "$(cat "$h/tool/AGENTS.md")" = "my own rules" ]; then
  pass "a stray that cannot be copied is left in place, not replaced by the link"
else
  fail "a file was replaced by the link although its copy failed (exit $RC)"
fi

[ "$fails" -eq 0 ]
