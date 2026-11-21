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

# ---------------------------------------------------------------------------
# check-claude-memory.sh
# ---------------------------------------------------------------------------
STUB='# Memory Index — DISABLED

Disabled by user policy. Do not write memories here.
Durable facts live in `~/.agents/AGENTS.md` (global rules) and the project'\''s
`AGENTS.md` / `session_compact.md` (project facts).
'
# A scratch home: one Claude project memory dir, named for a real scratch project.
new_mem_home() {
  local h enc
  h="$(mktemp -d -p "$T" memXXXXXX)"
  mkdir -p "$h/brain/backups" "$h/guard" "$h/proj" "$h/cache"
  enc="-$(printf '%s' "${h#/}/proj" | tr '/' '-')"
  mkdir -p "$h/claude/$enc/memory"
  printf '%s\n' "$enc" > "$h/enc"
  printf '%s\n' "$h"
}
mem_dir() { printf '%s/claude/%s/memory\n' "$1" "$(cat "$1/enc")"; }
# run_mem HOME [VAR=VALUE ...] — exit code in RC.
run_mem() {
  local h="$1"
  shift
  RC=0
  env HOME="$h" AGENTS_HOME="$h/brain" CLAUDE_PROJECTS_ROOT="$h/claude" GROK_MEMORY="$h/grokmem" \
    GUARD_DIR="$h/guard" AGENTS_CACHE_FILE="$h/cache/map" "$@" \
    bash "$HOOKS/check-claude-memory.sh" >/dev/null 2>&1 || RC=$?
}

# The archive cannot be written. The memory files are the only copy: they stay.
h="$(new_mem_home)"
d="$(mem_dir "$h")"
printf 'a fact worth keeping\n' > "$d/topic.md"
rm -rf "$h/brain/backups" && : > "$h/brain/backups"
run_mem "$h"
if [ "$RC" -ne 0 ] && [ "$(cat "$d/topic.md" 2>/dev/null)" = "a fact worth keeping" ]; then
  pass "memory files stay when their archive cannot be written"
else
  fail "memory files were wiped although the archive failed (exit $RC)"
fi

h="$(new_mem_home)"
printf 'grok fact\n' > "$h/grokfile"
mkdir -p "$h/grokmem" && mv "$h/grokfile" "$h/grokmem/fact.md"
rm -rf "$h/brain/backups" && : > "$h/brain/backups"
run_mem "$h"
if [ "$RC" -ne 0 ] && [ "$(cat "$h/grokmem/fact.md" 2>/dev/null)" = "grok fact" ]; then
  pass "the Grok memory directory stays when its archive cannot be written"
else
  fail "the Grok memory directory was removed although the archive failed (exit $RC)"
fi

# A MEMORY.md that carries the stub sentence and a real fact is not a stub.
h="$(new_mem_home)"
d="$(mem_dir "$h")"
printf '%s\n- [deploy](deploy.md) the deploy key lives in the vault\n' "$STUB" > "$d/MEMORY.md"
run_mem "$h"
packet="$(ls -d "$h"/brain/backups/claude-residue/*/ 2>/dev/null | head -n 1)"
if [ "$RC" -eq 2 ] && [ -n "$packet" ] && grep -rq 'the deploy key lives in the vault' "$packet" \
   && [ "$(cat "$d/MEMORY.md")" = "$(printf '%s' "$STUB")" ]; then
  pass "a MEMORY.md with the stub sentence and a real fact is captured as residue"
else
  fail "a fact hidden behind the stub sentence was called clean (exit $RC)"
fi
run_mem "$h"
if [ "$RC" -eq 0 ]; then
  pass "a memory directory that holds only the stub is clean"
else
  fail "the stub alone was captured as residue (exit $RC)"
fi

# Two captures before anyone merged: the first import must still be there.
h="$(new_mem_home)"
d="$(mem_dir "$h")"
printf 'first fact\n' > "$d/one.md"
run_mem "$h"
sleep 1
printf 'second fact\n' > "$d/two.md"
run_mem "$h"
if grep -q 'first fact' "$h/proj/claude_memory_import.md" 2>/dev/null \
   && grep -q 'second fact' "$h/proj/claude_memory_import.md"; then
  pass "a second capture is added to claude_memory_import.md, not written over it"
else
  fail "a second capture overwrote an unread claude_memory_import.md"
fi

# The memory directory is a symlink. Writing the stub through it would
# overwrite a file in the place it points at.
h="$(new_mem_home)"
d="$(mem_dir "$h")"
rmdir "$d"
mkdir -p "$h/elsewhere"
printf 'my own notes index\n' > "$h/elsewhere/MEMORY.md"
printf 'kept elsewhere\n' > "$h/elsewhere/topic.md"
ln -s "$h/elsewhere" "$d"
run_mem "$h"
packet="$(ls -d "$h"/brain/backups/claude-residue/*/ 2>/dev/null | head -n 1)"
if [ "$(cat "$h/elsewhere/MEMORY.md")" = "my own notes index" ] && [ -f "$h/elsewhere/topic.md" ] \
   && [ ! -L "$d" ] && [ "$(cat "$d/MEMORY.md" 2>/dev/null)" = "$(printf '%s' "$STUB")" ] \
   && [ -n "$packet" ] && grep -rq 'kept elsewhere' "$packet"; then
  pass "a symlinked memory directory: the target is untouched, its content is archived, the link becomes a stub directory"
else
  fail "a symlinked memory directory had its target written or was not archived (exit $RC)"
fi

[ "$fails" -eq 0 ]
