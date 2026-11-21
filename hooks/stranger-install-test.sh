#!/usr/bin/env bash
# stranger-install-test.sh — install this repo the way a person who is not its owner would.
#
#   STRANGER_TEST_DISPOSABLE=1 bash hooks/stranger-install-test.sh [source-checkout]
#
# This is a REAL install into $HOME: it replaces rules files, tool configs, the
# schedule, and git's global config. Run it only on a machine that is thrown
# away afterwards (the CI job `stranger`, or a sandbox with an empty home). It
# refuses without STRANGER_TEST_DISPOSABLE=1, and it refuses a home that
# already holds ~/.agents.
#
# What it walks through, as README.md tells a new person to:
#   1. They already have rules files, a deny rule, and a Claude memory of their own.
#   2. They fork and clone. setup.sh must stop before it changes anything, twice:
#      once because signing is not set up, once because the fork still points
#      at the upstream owner.
#   3. `1config fork-init` plans, then writes the four owner files and the repo name in AGENTS.md in one signed commit.
#   4. setup.sh installs and its own verify.sh ends in PASS with no warnings.
#   5. What they had was saved before it was replaced, as README.md says.
#   6. A project under their own owner is theirs: checkpoint.sh does not veto the push.
#   7. uninstall.sh --yes --restore-configs gives their files back and leaves no autonomy mode.
#
# No network: origin is a URL under the reserved .test name and is never fetched.
# Exit 0 every step held · 1 a step failed (it says which) · 2 refused to run.
set -uo pipefail

SRC="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")/..}" && pwd -P)"
[ "${STRANGER_TEST_DISPOSABLE:-0}" = 1 ] || {
  echo "stranger-install-test: this installs into \$HOME for real. Set STRANGER_TEST_DISPOSABLE=1 on a throwaway machine." >&2
  exit 2
}
[ ! -e "$HOME/.agents" ] || { echo "stranger-install-test: $HOME/.agents already exists; this is not a fresh machine" >&2; exit 2; }
# The repo's own gates behave differently under CI (a missing TeX is a failure
# there). A stranger's laptop is not CI.
unset CI

WORK="$(mktemp -d)"
OUT="$WORK/out"
mkdir -p "$OUT"
step=0
say()  { step=$((step + 1)); echo "[$step] $*"; }
fail() {
  echo "  FAIL  $*" >&2
  if [ -n "${LAST:-}" ] && [ -f "$LAST" ]; then
    if grep -q '^  FAIL \|^  WARN ' "$LAST"; then
      echo "  --- FAIL and WARN lines of $LAST" >&2
      grep '^  FAIL \|^  WARN \|^ERROR' "$LAST" >&2
    else
      echo "  --- last 30 lines of $LAST" >&2
      tail -n 30 "$LAST" >&2
    fi
  fi
  exit 1
}
# has PATTERN... — "does the piped text match", for use after a pipe. It reads
# all of its input before it searches. grep -q stops at the first match, the
# writer then dies of SIGPIPE, and under pipefail the pipeline is false although
# the text was found (and `! writer | grep -q X` is then true although X is
# there). Some greps stop early with output to /dev/null as well, so the input
# is taken whole first and grep reads it from a here-string.
has() {
  local _has_text
  _has_text="$(cat)"
  grep -q "$@" <<<"$_has_text"
}
ok()   { echo "  ok    $*"; }
# A listing of everything under $HOME except the checkout, gpg's own home, and
# the directories a GitHub runner keeps writing to while a job runs (its work
# tree, its own install, and its logs all live under the runner's home).
snapshot() {
  (cd "$HOME" && find . -mindepth 1 \
     -not -path './.agents*' -not -path './.gnupg*' \
     -not -path './work*' -not -path './runners*' -not -path './actions-runner*' \
     -printf '%p %s %l\n' | LC_ALL=C sort)
}
# same_home BEFORE  — fail, and show what moved, when the home is no longer BEFORE.
same_home() {
  local now
  now="$(snapshot)"
  [ "$now" = "$1" ] && return 0
  echo "  --- what changed under $HOME (< before, > after)" >&2
  diff <(printf '%s\n' "$1") <(printf '%s\n' "$now") | grep '^[<>]' | head -n 20 >&2
  return 1
}

say "a person with their own setup"
mkdir -p "$HOME/.claude/projects/-home-me-work/memory" "$HOME/.grok" "$HOME/.config/opencode"
printf 'my claude rules\n' > "$HOME/.claude/CLAUDE.md"
printf 'my grok rules\n' > "$HOME/.grok/AGENTS.md"
printf 'my opencode rules\n' > "$HOME/.config/opencode/AGENTS.md"
printf '{\n  "permissions": {"deny": ["Bash(my-own-deny *)"]},\n  "theme": "mine"\n}\n' > "$HOME/.claude/settings.json"
printf 'a thing I told Claude to remember\n' > "$HOME/.claude/projects/-home-me-work/memory/note.md"
# A second memory directory is a symlink to a folder of their own.
mkdir -p "$HOME/my-notes" "$HOME/.claude/projects/-home-me-linked"
printf 'my own index\n' > "$HOME/my-notes/MEMORY.md"
ln -s "$HOME/my-notes" "$HOME/.claude/projects/-home-me-linked/memory"
ok "three rules files, one deny rule, one memory"

say "fork and clone"
mkdir -p "$HOME/.agents"
(cd "$SRC" && git ls-files -z --cached --others --exclude-standard) \
  | (cd "$SRC" && xargs -0 -r sh -c 'for f; do [ -e "$f" ] && printf "%s\0" "$f"; done' sh) \
  | (cd "$SRC" && tar --null -T - -cf -) | tar -xf - -C "$HOME/.agents"
A="$HOME/.agents"
git -C "$A" init -q -b main
# -f: the project template tracks a file that its own .gitignore names.
git -C "$A" add -f -A
# Upstream history, as a fork receives it: commits by someone else, whose key this machine does not hold.
GIT_AUTHOR_NAME=upstream GIT_AUTHOR_EMAIL=upstream@example.test \
GIT_COMMITTER_NAME=upstream GIT_COMMITTER_EMAIL=upstream@example.test \
  git -C "$A" commit -q -m "upstream history"
git -C "$A" remote add origin https://git.example.test/Stranger/1config.git
ok "checkout at $A, origin https://git.example.test/Stranger/1config.git"

say "setup.sh before signing is set up: it must stop and change nothing"
before="$(snapshot)"
LAST="$OUT/setup-nosign.out"; rc=0
bash "$A/setup.sh" >"$LAST" 2>&1 || rc=$?
[ "$rc" -ne 0 ] || fail "setup.sh exited 0 with no signing key"
grep -q 'commit.gpgsign is not true' "$LAST" || fail "setup.sh did not name commit.gpgsign"
grep -q 'git has no signing key' "$LAST" || fail "setup.sh did not name the signing key"
grep -q 'stopped before it changed anything' "$LAST" || fail "setup.sh did not say it changed nothing"
same_home "$before" || fail "setup.sh changed the home before it stopped"
ok "exit $rc, names both fixes, home untouched"

say "git identity and a signing key"
gpg --batch --quiet --pinentry-mode loopback --passphrase '' \
  --quick-generate-key 'Stranger <stranger@example.test>' ed25519 sign never >/dev/null 2>&1 \
  || fail "could not make a throwaway gpg key"
FPR="$(gpg --batch --list-keys --with-colons stranger@example.test | awk -F: '$1 == "fpr" { print $10; exit }')"
git config --global user.name Stranger
git config --global user.email stranger@example.test
git config --global user.signingkey "$FPR"
git config --global commit.gpgsign true
ok "key $FPR"

say "setup.sh on a fork that still points upstream: it must stop and name fork-init"
before="$(snapshot)"
LAST="$OUT/setup-nofork.out"; rc=0
bash "$A/setup.sh" >"$LAST" 2>&1 || rc=$?
[ "$rc" -ne 0 ] || fail "setup.sh exited 0 on a fork that was not initialised"
grep -q 'BRAIN_REMOTE does not list it' "$LAST" || fail "setup.sh did not say origin is unlisted"
grep -q '1config fork-init' "$LAST" || fail "setup.sh did not name fork-init"
same_home "$before" || fail "setup.sh changed the home before it stopped"
ok "exit $rc, names fork-init, home untouched"

say "fork-init: a plan first, then one signed commit"
head_before="$(git -C "$A" rev-parse HEAD)"
LAST="$OUT/fork-plan.out"
bash "$A/bin/1config" fork-init >"$LAST" 2>&1 || fail "fork-init plan exited non-zero"
grep -q '^== plan only' "$LAST" || fail "fork-init did not print a plan"
[ "$(git -C "$A" rev-parse HEAD)" = "$head_before" ] && [ -z "$(git -C "$A" status --porcelain)" ] \
  || fail "fork-init changed the checkout without --yes"
LAST="$OUT/fork-yes.out"
bash "$A/bin/1config" fork-init --yes >"$LAST" 2>&1 || fail "fork-init --yes exited non-zero"
grep -qx 'https://git.example.test/Stranger/1config.git' "$A/BRAIN_REMOTE" || fail "BRAIN_REMOTE lacks the origin URL"
grep -qx 'git@git.example.test:Stranger/1config.git' "$A/BRAIN_REMOTE" || fail "BRAIN_REMOTE lacks the ssh form"
! grep -qi 'FirstIntegral' "$A/BRAIN_REMOTE" "$A/NOTES_REMOTE" "$A/fork-parents.txt" \
  || fail "an upstream owner line survived in the owner files"
[ "$(grep -cv '^#' "$A/BRAIN_SIGNERS")" -eq 1 ] && grep -qx "$FPR" "$A/BRAIN_SIGNERS" \
  || fail "BRAIN_SIGNERS is not exactly this machine's key"
[ -z "$(sed -n '/^#/d;/^$/d;p' "$A/NOTES_REMOTE")" ] || fail "NOTES_REMOTE still names a repo"
[ "$(git -C "$A" log -1 --format='%G?')" = G ] || [ "$(git -C "$A" log -1 --format='%G?')" = U ] \
  || fail "the fork-init commit is not signed"
[ "$(git -C "$A" diff --name-only HEAD~1 HEAD | LC_ALL=C sort | tr '\n' ' ')" = "AGENTS.md BRAIN_REMOTE BRAIN_SIGNERS BRAIN_SIGNERS.asc NOTES_REMOTE fork-parents.txt " ] \
  || fail "the fork-init commit holds something other than the owner files, the key file, and AGENTS.md"
gpg --batch --show-keys --with-colons "$A/BRAIN_SIGNERS.asc" 2>/dev/null | has "$FPR" \
  || fail "BRAIN_SIGNERS.asc is not this person's public key"
grep -qF 'The GitHub repo is `Stranger/1config`' "$A/AGENTS.md" || fail "AGENTS.md still names the upstream repo"
bash "$A/bin/1config" fork-init >"$OUT/fork-again.out" 2>&1 && grep -q 'Nothing to do' "$OUT/fork-again.out" \
  || fail "a second fork-init did not say there is nothing to do"
ok "four owner files and the repo name in AGENTS.md, one signed commit, a second run is a no-op"

say "setup.sh: install, and its verify.sh must pass with no warnings"
# A machine that installed before 2026-11-21 has git's gpg.program set to a
# wrapper script that no longer exists. git then cannot sign or check anything.
# setup.sh has to clear that itself, before its own preflight asks git about HEAD.
git config --global gpg.program "$A/hooks/gpg-git.sh"
LAST="$OUT/setup.out"; rc=0
bash "$A/setup.sh" >"$LAST" 2>&1 || rc=$?
[ "$rc" -eq 0 ] || fail "setup.sh exited $rc"
grep -q '^== PASS (warnings=0) ==' "$LAST" || fail "verify.sh did not end in PASS (warnings=0)"
[ "$(readlink -f "$HOME/.claude/CLAUDE.md")" = "$A/AGENTS.md" ] || fail "~/.claude/CLAUDE.md is not the link"
[ -z "$(git config --global --get gpg.program 2>/dev/null || true)" ] \
  || fail "setup.sh set git's gpg.program; git must call gpg itself"
ok "installed, verify PASS (warnings=0)"

say "what they had was saved before it was replaced"
B="$(ls -d "$A"/backups/setup-* | head -n 1)"
[ "$(cat "$B/rules-claude-CLAUDE.md")" = "my claude rules" ] || fail "their CLAUDE.md was not saved"
[ "$(cat "$B/rules-grok-AGENTS.md")" = "my grok rules" ] || fail "their Grok rules were not saved"
[ "$(cat "$B/rules-config-opencode-AGENTS.md")" = "my opencode rules" ] || fail "their OpenCode rules were not saved"
grep -q 'my-own-deny' "$B/claude-settings.json" || fail "their Claude settings were not saved"
grep -rq 'a thing I told Claude to remember' "$B"/claude-memory-* || fail "their Claude memory was not archived"
[ "$(cat "$HOME/my-notes/MEMORY.md")" = "my own index" ] || fail "a symlinked memory directory had its target overwritten"
grep -rq 'my own index' "$B"/claude-memory-* || fail "the content behind a symlinked memory directory was not archived"
! grep -q 'my-own-deny' "$HOME/.claude/settings.json" || fail "README says their deny rule is replaced; it survived"
grep -q '"bypassPermissions"' "$HOME/.claude/settings.json" || fail "the opinionated default is not on"
[ -f "$B/config.toml.absent" ] && [ -f "$B/opencode-perms.jsonc.absent" ] || fail "new tool configs were not marked absent"
ok "rules, settings, and memory are in $B"

say "a project under their own owner is theirs"
P="$HOME/Projects/demo"
mkdir -p "$P"
git -C "$P" init -q -b main
printf 'demo\n' > "$P/README.md"
git -C "$P" add -A && git -C "$P" commit -q -m first
git -C "$P" remote add origin https://git.example.test/Stranger/demo.git
LAST="$OUT/checkpoint.out"; rc=0
bash "$A/hooks/checkpoint.sh" "$P" --dry-run -m "checkpoint: test" >"$LAST" 2>&1 || rc=$?
[ "$rc" -ne 14 ] && [ "$rc" -ne 15 ] || fail "checkpoint.sh vetoed the stranger's own repo (exit $rc)"
ok "checkpoint.sh --dry-run exit $rc (not the owner veto)"

say "the way out: uninstall --yes --restore-configs"
LAST="$OUT/uninstall.out"; rc=0
bash "$A/uninstall.sh" --yes --restore-configs >"$LAST" 2>&1 || rc=$?
[ "$rc" -eq 0 ] || fail "uninstall.sh exited $rc"
[ ! -L "$HOME/.claude/CLAUDE.md" ] && [ "$(cat "$HOME/.claude/CLAUDE.md")" = "my claude rules" ] || fail "their CLAUDE.md did not come back"
[ "$(cat "$HOME/.grok/AGENTS.md")" = "my grok rules" ] || fail "their Grok rules did not come back"
grep -q 'my-own-deny' "$HOME/.claude/settings.json" || fail "their Claude settings did not come back"
! grep -q bypassPermissions "$HOME/.claude/settings.json" || fail "bypassPermissions is still on after the restore"
[ ! -e "$HOME/.grok/config.toml" ] && [ ! -e "$HOME/.config/opencode/opencode.jsonc" ] \
  || fail "a tool config that 1config created is still there"
[ -z "$(git config --global --get gpg.program || true)" ] || fail "git's gpg.program still points at the repo"
ok "their files are back and no autonomy mode is left"

rm -rf "$WORK"
echo "== stranger install: all $step steps held =="
